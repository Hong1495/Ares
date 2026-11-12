import Foundation
import Combine

/// Global application state for synchronization across all views
@MainActor
class AppState: ObservableObject {
    static let shared = AppState()

    struct OperationStatus: Equatable {
        let title: String
    }

    // Clash Mode
    @Published var currentMode: ClashConfig.Mode = .rule

    // Navigation State
    enum NavigationItem: Hashable {
        case dashboard
        case policies
        case connections
        case analysis
        case topology
        case routeMap
        case logs
        case settings

        var displayName: String {
            switch self {
            case .dashboard: return "Dashboard"
            case .policies: return "Proxy & Rules"
            case .connections: return "Activity"
            case .analysis: return "Analysis"
            case .topology: return "Topology"
            case .routeMap: return "Routing"
            case .logs: return "Logs"
            case .settings: return "Settings"
            }
        }
    }
    @Published var selection: NavigationItem = .dashboard
    @Published var animationsEnabled: Bool = true
    var isForeground = true
    var didSendInitialWake = false

    // System toggles
    @Published var systemProxyEnabled = false
    @Published var tunEnabled = false

    // IP Information (Shared across components)
    @Published var publicIP: String = "Fetching..."
    @Published var countryCode: String?

    // Toggle state guards to prevent race conditions during fast switching
    var isMITMToggling = false
    var isTUNToggling = false
    var isSystemProxyToggling = false

    // Computed property for UI binding
    var mitmEnabled: Bool {
        NetworkMITMService.shared.isRunning
    }

    // Statistics
    @Published var activeConnectionsCount: Int? = 0
    var isSyncingStatus = false
    @Published private(set) var operationStatus: OperationStatus?
    @Published private(set) var lastOperationError: String?

    let clashController = ClashController.shared
    let clashViewModel = ClashViewModel.shared
    let systemProxyManager = SystemProxyManager.shared

    private var pollingTimer: AnyCancellable?

    private init() {
        // Restore properties synchronously where possible
        currentMode = ClashConfig.Mode(rawValue: UserDefaults.standard.string(forKey: DefaultsKeys.clashMode) ?? "rule") ?? .rule
        tunEnabled = UserDefaults.standard.bool(forKey: DefaultsKeys.tunEnabled)

        // Start polling timer (Unified Heartbeat)
        // 降低轮询频率：从 3 秒改为 10 秒以减少 CPU 占用
        pollingTimer = Timer.publish(every: 10.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }

                // OPTIMIZATION: Pause heartbeat in background
                guard self.isForeground && self.animationsEnabled else { return }

                Task {
                    self.syncStatus()
                }
            }
    }

    var isPerformingNetworkOperation: Bool {
        operationStatus != nil
    }

    func beginOperation(_ title: String) -> Bool {
        guard operationStatus == nil, !clashViewModel.isToggling else {
            clashViewModel.addLog("[AppState] Ignored \(title) while \(operationStatus?.title ?? "another operation") is in progress", level: .warning)
            return false
        }

        lastOperationError = nil
        operationStatus = OperationStatus(title: title)
        return true
    }

    func clearOperationError() { lastOperationError = nil }

    func reportError(_ error: String) {
        lastOperationError = error
        clashViewModel.addLog(error, level: .error)
    }

    func finishOperation(error: String? = nil) {
        operationStatus = nil
        lastOperationError = error
        if let error {
            clashViewModel.addLog("[AppState] \(error)", level: .error)
        }
    }

    // Implementation moved to AppState+*.swift extensions.
}
