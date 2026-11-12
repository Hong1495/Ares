import Foundation
import Combine

/// Traffic statistics
struct TrafficStats: Codable {
    var up: Int64 = 0
    var down: Int64 = 0
}

/// Clash Rule
struct ClashRule: Codable, Identifiable {
    let id: UUID
    let type: String
    let payload: String
    let proxy: String
    let hit: Int
}

/// Represents a topological connection chain
struct ConnectionChain: Identifiable, Equatable {
    let id: String
    let host: String
    let sourceProcess: String
    let rule: String
    let chains: [String] // e.g. ["Rule", "HK Node", "Final"]
    let destinationIP: String
    let download: Int64
    let upload: Int64

    static func == (lhs: ConnectionChain, rhs: ConnectionChain) -> Bool {
        lhs.id == rhs.id && lhs.download == rhs.download && lhs.upload == rhs.upload && lhs.sourceProcess == rhs.sourceProcess && lhs.host == rhs.host && lhs.chains == rhs.chains && lhs.rule == rhs.rule
    }
}

/// Controller for interacting with Clash API
@MainActor
class ClashController: ObservableObject {
    static let shared = ClashController()

    // Dynamic base URL based on actual running mode
    var currentPort: Int = ClashPorts.apiNormal  // Default to Normal mode
    var baseURL: String {
        return "http://127.0.0.1:\(currentPort)"
    }

    /// Update the API port based on current TUN state
    func updatePort(tunEnabled: Bool) {
        runtimeGeneration = UUID()
        currentPort = tunEnabled ? ClashPorts.apiTun : ClashPorts.apiNormal
    }

    var selectingProxyGroups: Set<String> = []
    var runtimeGeneration = UUID() {
        didSet { measuredDelays.removeAll() }
    }
    @Published var testingProxyNames: Set<String> = []
    @Published var isTestingAllProxies = false
    var measuredDelays: [String: Int] = [:]
    var automaticLatencyTask: Task<Void, Never>?
    var proxySession: URLSession = .shared
    @Published var traffic = TrafficStats()
    @Published var proxies: [String: Any] = [:]
    @Published var proxyGroups: [ProxyGroup] = []
    @Published var proxyNodes: [String: ProxyNode] = [:]

    @Published var rules: [ClashRule] = []

    // Topology Data
    @Published var activeChains: [ConnectionChain] = []

    /// Resolved primary node name (without latency lookup)
    var primaryNodeName: String? {
        let allGroups = proxyGroups
        var activeGroupName: String? = nil

        if AppState.shared.currentMode == .global {
            activeGroupName = "GLOBAL"
        } else {
            if allGroups.contains(where: { $0.name == "🚀 节点选择" }) { activeGroupName = "🚀 节点选择" }
            else if allGroups.contains(where: { $0.name == "Proxy" }) { activeGroupName = "Proxy" }
            else if let fallback = allGroups.first(where: { $0.type == "Selector" && $0.name != "GLOBAL" }) { activeGroupName = fallback.name }
        }

        guard let gName = activeGroupName,
              let group = allGroups.first(where: { $0.name == gName }),
              let finalNode = group.resolveCurrentPath(groups: allGroups).last else {
            return nil
        }
        return finalNode
    }

    /// Current primary latency for display
    var primaryLatency: Int? {
        guard let name = primaryNodeName else { return nil }
        return proxyNodes[name]?.delay
    }

    var statusSubscription: AnyCancellable?
    var refreshTimer: Timer?

    // Retry limiting
    var consecutiveFailures = 0
    let MAX_RETRY_FAILURES = 5

    // Traffic monitoring state
    var trafficWebSocket: URLSessionWebSocketTask?
    var isMonitoring = false
    var lastTrafficUpdate: Date = Date()
    var lastTrafficStats: TrafficStats = TrafficStats()

    private init() {
        setupLifecycleObserver()
    }

    deinit {
        refreshTimer?.invalidate()
    }
}
