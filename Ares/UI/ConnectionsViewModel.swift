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
    private var monitoringRevision = UUID()
    private var cancellables = Set<AnyCancellable>()
    private var lastConnectionsUpdate: Date = .distantPast
    private let minConnectionsInterval: TimeInterval = 1.0
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
            .sink { [weak self] _ in
                Task { await self?.startMonitoring() }
            }
            .store(in: &cancellables)

        ClashViewModel.shared.$runtimeState.combineLatest(ClashViewModel.shared.$isToggling)
            .receive(on: RunLoop.main)
            .sink { [weak self] state, toggling in
                self?.stopMonitoring()
                if state == .running && !toggling {
                    Task { await self?.startMonitoring() }
                }
            }
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
        guard AppState.shared.isForeground, ClashViewModel.shared.isRunning, !ClashViewModel.shared.isToggling else { return }
        if !isRetry {
            guard !isMonitoring else { return }
            isMonitoring = true
        }

        let tunEnabled = AppState.shared.tunEnabled
        let port = tunEnabled ? ClashPorts.apiTun : ClashPorts.apiNormal
        guard let url = URL(string: "ws://127.0.0.1:\(port)/connections") else { return }

        monitoringRevision = UUID()
        webSocketTask?.cancel()
        webSocketTask = URLSession.shared.webSocketTask(with: url)
        webSocketTask?.resume()

        await receiveMessages()
    }

    func stopMonitoring() {
        isMonitoring = false
        monitoringRevision = UUID()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
    }

    private func receiveMessages() async {
        guard AppState.shared.isForeground else {
            stopMonitoring()
            return
        }
        guard let webSocket = webSocketTask else { return }
        let revision = monitoringRevision
        do {
            let message = try await webSocket.receive()
            guard revision == monitoringRevision else { return }
            switch message {
            case .string(let text): parseConnectionsData(text)
            case .data(let data): if let text = String(data: data, encoding: .utf8) { parseConnectionsData(text) }
            @unknown default: break
            }
            if isMonitoring { await receiveMessages() }
        } catch {
            if isMonitoring, revision == monitoringRevision {
                Task {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    guard self.isMonitoring, revision == self.monitoringRevision else { return }
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

        let revision = monitoringRevision
        let generation = ClashController.shared.runtimeGeneration
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            defer {
                Task { @MainActor in
                    self.isProcessingConnections = false
                }
            }

            let parsed = ConnectionSnapshot.decode(Data(jsonString.utf8))
            let resolved = await ConnectionProcessResolver.shared.resolve(parsed)
            guard generation == (await ClashController.shared.runtimeGeneration) else { return }
            let filteredConnections = resolved.filter { !$0.identity.isAres }

            // 2. Update Traffic Audit (MainActor, but internal logic is backgrounded)
            await TrafficAuditManager.shared.update(with: filteredConnections)

            // 3. Process Speed & Grouping (Background Actor)
            // Fetch latest sessions from MainActor before going to background
            let sessions = await TrafficAuditManager.shared.sessions
            let mode = await MainActor.run { self.groupingMode }

            let nodes = await self.calculator.process(rawConnections: filteredConnections, appSessions: sessions, groupingMode: mode)

            // 4. Update UI
            await MainActor.run {
                guard revision == self.monitoringRevision, generation == ClashController.shared.runtimeGeneration else { return }
                self.lastRawConnections = filteredConnections
                self.groupedNodes = nodes
            }
        }
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
