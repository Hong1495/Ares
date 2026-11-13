import Foundation
import Combine
import SubscriptionKit

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
    private(set) var verifiedMixedPort: Int?
    private(set) var verifiedSocksPort: Int?
    private(set) var activeCheckpoint: RuntimeCheckpoint?

    /// Capture the running file, not a candidate already written to config.yaml.
    func recoveryCheckpoint() throws -> RuntimeCheckpoint {
        guard runtimeState.isAPIReady, let checkpoint = activeCheckpoint else {
            throw NSError(domain: "Runtime", code: 1, userInfo: [NSLocalizedDescriptionKey: "No verified running configuration is available for recovery."])
        }
        return RuntimeCheckpoint(configuration: checkpoint.configuration, profileID: checkpoint.profileID,
            profileRevision: checkpoint.profileRevision,
            selections: checkpoint.profileRevision == ProfileService.shared.activeProfileRevision
                ? ProfileService.shared.savedSelections() : checkpoint.selections,
            tunEnabled: checkpoint.tunEnabled, verifiedAt: checkpoint.verifiedAt)
    }
    func captureRecoveryCheckpoint() async throws -> RuntimeCheckpoint {
        let checkpoint = try recoveryCheckpoint()
        let generation = ClashController.shared.runtimeGeneration
        let data = try await ClashController.shared.readRuntimeConfiguration()
        guard generation == ClashController.shared.runtimeGeneration, runtimeState.isAPIReady else { throw CancellationError() }
        let content = try ConfigurationAudit.recoveryConfiguration(configuration: checkpoint.configuration, response: data)
        let updated = RuntimeCheckpoint(configuration: content, profileID: checkpoint.profileID,
            profileRevision: checkpoint.profileRevision, selections: checkpoint.selections,
            tunEnabled: checkpoint.tunEnabled)
        activeCheckpoint = updated
        return updated
    }

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
    func startCore(isRestart: Bool = false, preparedConfiguration: String? = nil, recovery: RuntimeCheckpoint? = nil, persistCheckpoint: Bool = true) async {
        // Sync Controller port with App State BEFORE activating monitors
        let tunEnabled = await MainActor.run { AppState.shared.tunEnabled }
        ClashController.shared.updatePort(tunEnabled: tunEnabled)

        let profileRevision = recovery?.profileRevision ?? ProfileService.shared.activeProfileRevision
        let requestedRevision = ProfileService.shared.activeProfileRevision
        guard recovery == nil || recovery?.tunEnabled == tunEnabled else {
            runtimeState = .failed("Recovery configuration does not match the requested mode")
            return
        }
        let selectedProfileID = recovery.map(\.profileID) ?? ProfileService.shared.activeProfileID
        let selections = recovery?.selections ?? ProfileService.shared.savedSelections()
        appliedProfileRevision = ""
        runtimeState = .launching
        AppState.shared.activeConnectionsCount = nil
        let started = await ClashServiceActor.shared.start(isRestart: isRestart, preparedConfiguration: recovery?.configuration ?? preparedConfiguration)

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
                try await ProfileService.shared.restoreNodeSelections(choices: selections)
                guard requestedRevision == ProfileService.shared.activeProfileRevision else { throw CancellationError() }
                let data = try await ClashController.shared.readRuntimeConfiguration()
                try CoreAPIContract.verifyTUN(data, expected: tunEnabled)
                let config = try await ConfigService.shared.savedConfiguration(tunEnabled: tunEnabled)
                try ConfigurationAudit.verifyStartup(configuration: config, response: data)
                try await ClashServiceActor.shared.verifyAdditionalListeners(configuration: config, tunEnabled: tunEnabled)
                guard requestedRevision == ProfileService.shared.activeProfileRevision else { throw CancellationError() }
                let runtime = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                verifiedMixedPort = runtime?["mixed-port"] as? Int
                verifiedSocksPort = runtime?["socks-port"] as? Int
                let checkpoint = RuntimeCheckpoint(configuration: config, profileID: selectedProfileID,
                    profileRevision: profileRevision, selections: selections, tunEnabled: tunEnabled)
                activeCheckpoint = checkpoint
                if persistCheckpoint { await persistActiveCheckpoint() }
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
    
    func persistActiveCheckpoint() async {
        guard let checkpoint = activeCheckpoint else { return }
        do { try await ConfigService.shared.rememberSuccessfulRuntime(checkpoint) }
        catch { addLog("[Config] Runtime verified, but recovery snapshot could not be saved", level: .warning) }
    }

    @discardableResult
    func stopCore(intendedRestart: Bool = false) async -> Bool {
        appliedProfileRevision = ""
        verifiedMixedPort = nil
        verifiedSocksPort = nil
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
        guard AppState.shared.beginOperation("Restarting Core") else { return }
        isToggling = true
        defer {
            isToggling = false
            AppState.shared.finishOperation(error: AppState.shared.lastOperationError)
        }
        guard runtimeState.isAPIReady else { await startCore(isRestart: true); return }
        do {
            let checkpoint = try await captureRecoveryCheckpoint()
            let result = await ConfigurationCoordinator.replace(previous: checkpoint,
                targetMode: AppState.shared.tunEnabled, restoreProxy: AppState.shared.systemProxyEnabled)
            if result != .committed { AppState.shared.reportError("Restart did not commit (\(result)). Check the runtime status.") }
        } catch { AppState.shared.reportError("No verified configuration is available for restart recovery.") }
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

    func handleUnexpectedExit() {
        guard runtimeState.isAPIReady, !isToggling, !AppTerminationCoordinator.shared.isCleaningUp else { return }
        isRunning = false
        verifiedMixedPort = nil
        verifiedSocksPort = nil
        appliedProfileRevision = ""
        runtimeState = .failed("The core exited unexpectedly")
        ClashController.shared.runtimeGeneration = UUID()
        ClashController.shared.stopTrafficMonitor()
        AppState.shared.activeConnectionsCount = nil
        Task { @MainActor in
            let app = AppState.shared
            guard app.beginOperation("Restoring Network After Core Exit") else {
                app.reportError("The core exited. Check the system proxy before reconnecting.")
                return
            }
            defer { app.finishOperation(error: app.lastOperationError) }
            if app.systemProxyEnabled {
                if await SystemProxyManager.shared.setSystemProxy(enabled: false) {
                    app.systemProxyEnabled = false
                    // Keep the saved user preference for a later deliberate reconnect.
                } else {
                    app.reportError("The core exited and the system proxy could not be restored. Recovery is required.")
                    return
                }
            }
            app.reportError("The core exited. Restart or restore the last verified configuration to reconnect.")
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
