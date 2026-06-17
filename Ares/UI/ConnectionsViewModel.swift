import Foundation
import Combine

@MainActor
final class ConnectionsViewModel: ObservableObject {
    @Published var groupedNodes: [ActivityNode] = []

    // Grouping
    @Published var groupingMode: GroupingMode = .app {
        didSet { recomputeNodes() }
    }

    // Raw Data (Cached for regrouping without new data)
    private var lastRawConnections: [Connection] = []

    // Public readonly access to connections for UI/Export
    var connections: [Connection] { lastRawConnections }

    // Dependencies
    private let calculator = ConnectionsCalculator()
    private var webSocketTask: URLSessionWebSocketTask?
    private var isMonitoring = false
    private var cancellables = Set<AnyCancellable>()
    private var lastConnectionsUpdate: Date = .distantPast
    private let minConnectionsInterval: TimeInterval = 0.25
    private var isProcessingConnections = false

    var totalDownload: Int64 {
        // TrafficAuditManager.shared.sessions is source of truth
        TrafficAuditManager.shared.sessions.reduce(0) { $0 + $1.totalDownload }
    }

    var totalUpload: Int64 {
        TrafficAuditManager.shared.sessions.reduce(0) { $0 + $1.totalUpload }
    }

    init() {
        // MARK: - Global Lifecycle (Event Bus)
        NotificationCenter.default.publisher(for: .appDidGoSilent)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.stopMonitoring()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .appDidWakeUp)
            .receive(on: RunLoop.main)
            .sink { _ in }
            .store(in: &cancellables)
    }

    func resetStatistics() {
        TrafficAuditManager.shared.reset()
    }

    private func recomputeNodes() {
        Task {
            let sessions = TrafficAuditManager.shared.sessions
            let nodes = await calculator.regroup(connections: self.lastRawConnections, sessions: sessions, mode: self.groupingMode)
            self.groupedNodes = nodes
        }
    }

    // MARK: - Monitoring

    func startMonitoring(isRetry: Bool = false) async {
        guard AppState.shared.isForeground else { return }
        if !isRetry {
            guard !isMonitoring else { return }
            isMonitoring = true
        }

        let tunEnabled = AppState.shared.tunEnabled
        let port = tunEnabled ? ClashPorts.apiTun : ClashPorts.apiNormal
        guard let url = URL(string: "ws://127.0.0.1:\(port)/connections") else { return }

        webSocketTask?.cancel()
        webSocketTask = URLSession.shared.webSocketTask(with: url)
        webSocketTask?.resume()

        await receiveMessages()
    }

    func stopMonitoring() {
        isMonitoring = false
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
    }

    private func receiveMessages() async {
        guard AppState.shared.isForeground else {
            stopMonitoring()
            return
        }
        guard let webSocket = webSocketTask else { return }
        do {
            let message = try await webSocket.receive()
            switch message {
            case .string(let text): parseConnectionsData(text)
            case .data(let data): if let text = String(data: data, encoding: .utf8) { parseConnectionsData(text) }
            @unknown default: break
            }
            if isMonitoring { await receiveMessages() }
        } catch {
            if isMonitoring {
                Task {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    await self.startMonitoring(isRetry: true)
                }
            }
        }
    }

    private func parseConnectionsData(_ jsonString: String) {
        let now = Date()
        guard now.timeIntervalSince(lastConnectionsUpdate) >= minConnectionsInterval else { return }
        guard !isProcessingConnections else { return }
        lastConnectionsUpdate = now
        isProcessingConnections = true

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            defer {
                Task { @MainActor in
                    self.isProcessingConnections = false
                }
            }

            // 1. Parse JSON (Pure func)
            let parsedConnections = Self.parseJSON(jsonString)

            // Critical: Filter out "Ares" self-traffic
            let filteredConnections = parsedConnections.filter { conn in
                guard let path = conn.metadata.processPath else { return false }
                let process = (path as NSString).lastPathComponent
                return !(process.localizedCaseInsensitiveContains("Ares") ||
                         process.localizedCaseInsensitiveContains("com.herastudio.ares") ||
                         path.contains("/Ares.app/"))
            }

            // 2. Update Traffic Audit (MainActor, but internal logic is backgrounded)
            await TrafficAuditManager.shared.update(with: filteredConnections)

            // 3. Process Speed & Grouping (Background Actor)
            // Fetch latest sessions from MainActor before going to background
            let sessions = await TrafficAuditManager.shared.sessions
            let mode = await MainActor.run { self.groupingMode }

            let nodes = await self.calculator.process(rawConnections: filteredConnections, appSessions: sessions, groupingMode: mode)

            // 4. Update UI
            await MainActor.run {
                self.lastRawConnections = filteredConnections
                self.groupedNodes = nodes
            }
        }
    }

    // Shared formatter to avoid expensive allocation in loop
    nonisolated(unsafe) private static let sharedDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated private static func parseJSON(_ jsonString: String) -> [Connection] {
         guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let connectionsDict = json["connections"] as? [[String: Any]] else {
            return []
        }

        var connections: [Connection] = []

        for connData in connectionsDict {
            guard let id = connData["id"] as? String,
                  let metadataDict = connData["metadata"] as? [String: Any],
                  let network = metadataDict["network"] as? String,
                  let type = metadataDict["type"] as? String,
                  let sourceIP = metadataDict["sourceIP"] as? String,
                  let destIP = metadataDict["destinationIP"] as? String,
                  let sourcePort = metadataDict["sourcePort"] as? String,
                  let destPort = metadataDict["destinationPort"] as? String,
                  let host = metadataDict["host"] as? String else {
                continue
            }

            let metadata = ConnectionMetadata(
                network: network,
                type: type,
                sourceIP: sourceIP,
                destinationIP: destIP,
                sourcePort: sourcePort,
                destinationPort: destPort,
                host: host,
                processPath: metadataDict["processPath"] as? String
            )

            let upload = connData["upload"] as? Int64 ?? 0
            let download = connData["download"] as? Int64 ?? 0
            let chains = connData["chains"] as? [String] ?? []
            let rule = connData["rule"] as? String ?? ""
            let rulePayload = connData["rulePayload"] as? String ?? ""

            var startDate = Date()
            if let startStr = connData["start"] as? String {
                startDate = Self.sharedDateFormatter.date(from: startStr) ?? Date()
            }

            let connection = Connection(
                id: id,
                metadata: metadata,
                upload: upload,
                download: download,
                start: startDate,
                chains: chains,
                rule: rule,
                rulePayload: rulePayload
            )
            connections.append(connection)
        }
        return connections
    }

    func closeConnection(id: String) async {
         let tunEnabled = AppState.shared.tunEnabled
         let port = tunEnabled ? ClashPorts.apiTun : ClashPorts.apiNormal
         guard let url = URL(string: "http://127.0.0.1:\(port)/connections/\(id)") else { return }
         var request = URLRequest(url: url)
         request.httpMethod = "DELETE"
         _ = try? await URLSession.shared.data(for: request)
     }
}
