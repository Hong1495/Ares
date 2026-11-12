import Foundation
import Combine

@MainActor
final class ConnectionsViewModel: ObservableObject {
    @Published var actionError: String?
    private var groupingRevision = UUID()
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

    var totalDownload: Int64 {
        // TrafficAuditManager.shared.sessions is source of truth
        TrafficAuditManager.shared.observedDownload
    }

    var totalUpload: Int64 {
        TrafficAuditManager.shared.observedUpload
    }

    init() {
        TrafficAuditManager.shared.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)

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
        Task {
            await TrafficAuditManager.shared.reset()
            recomputeNodes()
        }
    }

    private func recomputeNodes() {
        groupingRevision = UUID()
        let revision = groupingRevision
        let mode = groupingMode
        Task {
            let sessions = TrafficAuditManager.shared.sessions
            let nodes = await calculator.regroup(connections: lastRawConnections, sessions: sessions, mode: mode)
            guard revision == groupingRevision, mode == groupingMode else { return }
            groupedNodes = nodes
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
        guard let socket = webSocketTask else { return }
        let revision = monitoringRevision
        do {
            while isMonitoring, revision == monitoringRevision, AppState.shared.isForeground {
                let message = try await socket.receive()
                guard revision == monitoringRevision else { return }
                switch message {
                case .string(let text): await parseConnectionsData(Data(text.utf8), revision: revision)
                case .data(let data): await parseConnectionsData(data, revision: revision)
                @unknown default: break
                }
            }
        } catch {
            guard isMonitoring, revision == monitoringRevision else { return }
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.isMonitoring, revision == self.monitoringRevision else { return }
                await self.startMonitoring(isRetry: true)
            }
        }
    }

    private func parseConnectionsData(_ data: Data, revision: UUID) async {
        let generation = ClashController.shared.runtimeGeneration
        let parsed = ConnectionSnapshot.decode(data)
        let resolved = await ConnectionProcessResolver.shared.resolve(parsed)
        guard generation == ClashController.shared.runtimeGeneration, revision == monitoringRevision else { return }
        let filtered = resolved.filter { !$0.identity.isAres }
        await TrafficAuditManager.shared.update(with: filtered)
        guard generation == ClashController.shared.runtimeGeneration, revision == monitoringRevision else { return }
        let mode = groupingMode
        let result = await calculator.process(rawConnections: filtered,
                                              appSessions: TrafficAuditManager.shared.sessions,
                                              groupingMode: mode)
        guard generation == ClashController.shared.runtimeGeneration, revision == monitoringRevision else { return }
        lastRawConnections = result.connections
        if mode == groupingMode {
            groupingRevision = UUID()
            groupedNodes = result.nodes
        } else {
            recomputeNodes()
        }
    }

    func closeConnection(id: String) async {
         let tunEnabled = AppState.shared.tunEnabled
         let port = tunEnabled ? ClashPorts.apiTun : ClashPorts.apiNormal
         guard let url = URL(string: "http://127.0.0.1:\(port)/connections/\(id)") else { return }
         var request = URLRequest(url: url)
         request.httpMethod = "DELETE"
         do {
             let (_, response) = try await URLSession.shared.data(for: request)
             try CoreAPIContract.requireSuccess(response)
         } catch { actionError = "Could not close the connection. Please try again." }
     }
}
