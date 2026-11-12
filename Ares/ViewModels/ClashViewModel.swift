import Foundation
import Combine

/// ViewModel for Clash service - handles UI state only
/// Business logic delegated to ClashService actor
@MainActor
class ClashViewModel: ObservableObject {
    enum RuntimeState: Equatable {
        case stopped
        case launching
        case processRunning
        case apiReady
        case running
        case stopping
        case failed(String)

        var isActive: Bool {
            switch self {
            case .launching, .processRunning, .apiReady, .running:
                return true
            case .stopped, .stopping, .failed:
                return false
            }
        }

        var isAPIReady: Bool {
            switch self {
            case .apiReady, .running:
                return true
            default:
                return false
            }
        }

        var title: String {
            switch self {
            case .stopped: return "Stopped"
            case .launching: return "Launching"
            case .processRunning: return "Process running"
            case .apiReady: return "API ready"
            case .running: return "Running"
            case .stopping: return "Stopping"
            case .failed: return "Failed"
            }
        }

        var detail: String {
            switch self {
            case .failed(let message): return message
            default: return title
            }
        }
    }

    // MARK: - Published UI State
    @Published private(set) var appliedProfileRevision = ""
    @Published var isRunning: Bool = false
    @Published var logs: [String] = []
    @Published var isToggling: Bool = false
    @Published var runtimeState: RuntimeState = .stopped
    @Published var coreVersionInfo: CoreVersionInfo = .unknown
    @Published var latestCoreRelease: CoreReleaseInfo?
    @Published var isInstallingCoreUpdate = false
    @Published var coreUpdateMessage: String?
    
    // MARK: - Singleton
    static let shared = ClashViewModel()
    
    private init() {}
    
    // MARK: - Public Methods (UI-facing)
    
    func start(isRestart: Bool = false) async {
        guard !AppTerminationCoordinator.shared.isCleaningUp, !isToggling else { return }
        if isRunning && !isRestart { return }
        isToggling = true
        defer { isToggling = false }
        await startCore(isRestart: isRestart)
        if case .failed(let message) = runtimeState { AppState.shared.reportError(message) }
    }
    
    func stop(intendedRestart: Bool = false) async {
        guard !AppTerminationCoordinator.shared.isCleaningUp, !isToggling else { return }
        isToggling = true
        defer { isToggling = false }
        if !intendedRestart {
            guard await SystemProxyManager.shared.setSystemProxy(enabled: false) else {
                AppState.shared.reportError(SystemProxyManager.shared.lastError ?? "Proxy restoration failed; core kept running.")
                return
            }
            AppState.shared.systemProxyEnabled = false
        }
        guard await stopCore(intendedRestart: intendedRestart) else {
            AppState.shared.reportError("Core could not stop. The process was retained for recovery.")
            return
        }
        if !intendedRestart { await NetworkMITMService.shared.stop() }
    }
    
    /// Internal methods for core operations - NO GATING
    func startCore(isRestart: Bool = false) async {
        // Sync Controller port with App State BEFORE activating monitors
        let tunEnabled = await MainActor.run { AppState.shared.tunEnabled }
        ClashController.shared.updatePort(tunEnabled: tunEnabled)

        let profileRevision = ProfileService.shared.activeProfileRevision
        appliedProfileRevision = ""
        runtimeState = .launching
        AppState.shared.activeConnectionsCount = nil
        let started = await ClashServiceActor.shared.start(isRestart: isRestart)

        guard started else {
            isRunning = false
            if case .failed = runtimeState {
                return
            }
            runtimeState = .failed("Core failed to launch")
            return
        }

        runtimeState = .processRunning

        let readyTimeout: TimeInterval = tunEnabled ? 15.0 : 8.0
        if await ClashController.shared.waitForAPIReady(timeout: readyTimeout) {
            do {
                try await ProfileService.shared.restoreNodeSelections()
                guard profileRevision == ProfileService.shared.activeProfileRevision else { throw CancellationError() }
                // Read back TUN before reporting the runtime ready or enabling routing.
                guard let url = URL(string: "\(ClashController.shared.baseURL)/configs") else { throw URLError(.badURL) }
                let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 5))
                try CoreAPIContract.requireSuccess(response)
                try CoreAPIContract.verifyTUN(data, expected: tunEnabled)
                appliedProfileRevision = profileRevision
                runtimeState = .apiReady
                isRunning = true
                runtimeState = .running
            } catch {
                let stopped = await ClashServiceActor.shared.stop()
                isRunning = false
                runtimeState = .failed(stopped ? "Core configuration or node selection could not be confirmed" : "Core verification and cleanup failed")
            }
        } else {
            isRunning = false
            let stopped = await ClashServiceActor.shared.stop()
            runtimeState = .failed(stopped ? "Clash API did not become ready" : "API timeout; core stop also failed")
        }
    }
    
    @discardableResult
    func stopCore(intendedRestart: Bool = false) async -> Bool {
        appliedProfileRevision = ""
        runtimeState = .stopping
        ClashController.shared.runtimeGeneration = UUID()
        AppState.shared.activeConnectionsCount = nil
        self.isRunning = false
        guard await ClashServiceActor.shared.stop(intendedRestart: intendedRestart) else {
            runtimeState = .failed("Core stop failed; process may still be active")
            return false
        }
        AppState.shared.activeConnectionsCount = 0
        runtimeState = .stopped
        return true
    }
    
    func restart() async {
        // Global operation gate
        guard !AppTerminationCoordinator.shared.isCleaningUp, !isToggling else { return }
        isToggling = true
        defer { isToggling = false }
        
        guard await stopCore(intendedRestart: true) else { return }
        await startCore(isRestart: true)
    }
    
    /// Log levels matching Clash core levels
    enum LogLevel: Int, Comparable {
        case debug = 0
        case info = 1
        case warning = 2
        case error = 3
        case silent = 4
        
        static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
        
        static func from(string: String) -> LogLevel {
            switch string.lowercased() {
            case "debug": return .debug
            case "info": return .info
            case "warning": return .warning
            case "error": return .error
            case "silent": return .silent
            default: return .info
            }
        }
    }
    
    /// Add log message to UI with level filtering
    /// - Parameters:
    ///   - message: Log message
    ///   - level: Log level (default: .info)
    func addLog(_ message: String, level: LogLevel = .info) {
        // Get user's log level setting
        let userLogLevelString = UserDefaults.standard.string(forKey: DefaultsKeys.logLevel) ?? "info"
        let userLogLevel = LogLevel.from(string: userLogLevelString)
        
        // Filter: only show logs at or above user's level
        guard level >= userLogLevel else { return }
        
        let timestamp = DateFormatter.localizedString(
            from: Date(),
            dateStyle: .none,
            timeStyle: .medium
        )
        // Clean message to prevent newlines breaking list layout
        let cleanMessage = message.replacingOccurrences(of: "\n", with: " ")
        let logEntry = "[\(timestamp)] \(cleanMessage)"
        
        DispatchQueue.main.async {
            self.logs.append(logEntry)
            
            // Efficiently limit to last 1000 lines
            if self.logs.count > 1000 {
                self.logs.removeFirst(self.logs.count - 1000)
            }
        }
    }
    
    /// Clear all logs
    func clearLogs() {
        logs = []
    }
    
    /// Update running state from service
    /// - Parameter running: New running state
    func updateRunningState(_ running: Bool) {
        DispatchQueue.main.async {
            self.isRunning = running
            if !running, self.runtimeState != .stopping {
                self.runtimeState = .stopped
            }
        }
    }

    func markProcessLaunched() {
        runtimeState = .processRunning
    }

    func markStartFailed(_ message: String) {
        isRunning = false
        runtimeState = .failed(message)
    }

    func refreshCoreVersion() async {
        coreVersionInfo = await CoreManager.shared.versionInfo(forceRefresh: true)
    }

    func checkCoreUpdates() async {
        latestCoreRelease = await CoreManager.shared.latestRelease()
    }

    func installLatestCore() async {
        guard !isRunning, !isToggling, !isInstallingCoreUpdate else {
            coreUpdateMessage = "Stop core before installing updates"
            return
        }

        isInstallingCoreUpdate = true
        coreUpdateMessage = "Installing..."
        defer { isInstallingCoreUpdate = false }

        do {
            coreVersionInfo = try await CoreManager.shared.installLatestRelease()
            await PrivilegeService.shared.checkAndRepairSudoers()
            coreUpdateMessage = "Installed \(coreVersionInfo.displayVersion)"
            await checkCoreUpdates()
        } catch {
            coreUpdateMessage = error.localizedDescription
        }
    }

    func rollbackCore() async {
        guard !isRunning, !isToggling, !isInstallingCoreUpdate else {
            coreUpdateMessage = "Stop core before rollback"
            return
        }

        isInstallingCoreUpdate = true
        coreUpdateMessage = "Rolling back..."
        defer { isInstallingCoreUpdate = false }

        do {
            coreVersionInfo = try await CoreManager.shared.rollbackManagedCore()
            await PrivilegeService.shared.checkAndRepairSudoers()
            coreUpdateMessage = "Active \(coreVersionInfo.displayVersion)"
            await checkCoreUpdates()
        } catch {
            coreUpdateMessage = error.localizedDescription
        }
    }

    var isCoreUpdateAvailable: Bool {
        guard let latestCoreRelease else { return false }
        return CoreManager.shared.isUpdateAvailable(current: coreVersionInfo.displayVersion, latest: latestCoreRelease.version)
    }
}
