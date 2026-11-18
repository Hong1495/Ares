import AppKit
import Combine
import Network
import Sparkle

/// App updates only. Core binary updates remain a separate operation.
@MainActor
final class AppUpdateService: NSObject, ObservableObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    static let shared = AppUpdateService()
    @Published private(set) var availableVersion: String?
    @Published private(set) var status = ""
    @Published private(set) var isChecking = false
    @Published private(set) var isConfigured = false
    @Published var automaticallyChecks: Bool = UserDefaults.standard.object(forKey: "SUEnableAutomaticChecks") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(automaticallyChecks, forKey: "SUEnableAutomaticChecks")
            controller?.updater.automaticallyChecksForUpdates = automaticallyChecks
            if automaticallyChecks {
                startAutomaticRecovery()
            } else {
                stopAutomaticRecovery()
            }
        }
    }
    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    private var controller: SPUStandardUpdaterController?
    private var pendingInstall: (() -> Void)?
    private var preparingInstall = false
    private var installGeneration = UUID()
    private var canCheckObservation: NSKeyValueObservation?
    private var recovery: AppUpdateRecovery
    private var retryTask: Task<Void, Never>?
    private var pathMonitor: NWPathMonitor?
    private var pathWasAvailable: Bool?
    private var activeObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var loadedFeedForCurrentCheck = false
    @Published private(set) var canCheck = false

    init(recovery: AppUpdateRecovery? = nil) {
        self.recovery = recovery ?? AppUpdateRecovery()
        super.init()
    }

    func start() {
        guard controller == nil else { return }
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              Data(base64Encoded: key)?.count == 32,
              let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              URL(string: feed)?.scheme == "https" else {
            status = "Updates are not configured in this build."
            return
        }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
        self.controller = controller
        do {
            try controller.updater.start()
            controller.updater.automaticallyChecksForUpdates = automaticallyChecks
            // Quiet checks are automatic; installing remains an explicit user action.
            controller.updater.automaticallyDownloadsUpdates = false
            canCheckObservation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                let allowed = updater.canCheckForUpdates
                Task { @MainActor [weak self] in self?.canCheck = allowed }
            }
            isConfigured = true
            record("Started Ares \(currentVersion) (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") ?? "—")), PID \(ProcessInfo.processInfo.processIdentifier), path \(Bundle.main.bundlePath)")
            // Sparkle explicitly supports a launch-time background check immediately after start.
            if automaticallyChecks {
                startAutomaticRecovery()
                controller.updater.checkForUpdatesInBackground()
            }
        } catch {
            status = error.localizedDescription
            self.controller = nil
        }
    }

    func checkForUpdates() {
        if controller == nil { start() }
        guard let controller, !preparingInstall else { return }
        if pendingInstall != nil { resumeInstallation(); return }
        // Bringing an existing update window into focus does not start a new check.
        if controller.updater.sessionInProgress {
            controller.checkForUpdates(nil)
            return
        }
        guard controller.updater.canCheckForUpdates, !isChecking else { return }
        isChecking = true
        status = "Checking for updates…"
        controller.checkForUpdates(nil)
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        guard let base = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String else { return nil }
        return base.replacingOccurrences(of: "appcast.xml", with: "appcast-arm64.xml")
    }

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool { false }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        availableVersion = update.displayVersionString
        isChecking = false
        status = "Ares \(update.displayVersionString) is available."
    }

    func standardUserDriverWillFinishUpdateSession() {
        availableVersion = nil
        isChecking = false
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        availableVersion = item.displayVersionString
        status = "Ares \(item.displayVersionString) is available."
        isChecking = false
        record("Found Ares \(item.displayVersionString); update indicator is available")
    }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        cancelRetry()
        loadedFeedForCurrentCheck = false
        recovery.checkStarted(at: Date())
        record("Checking for updates (\(updateCheck.rawValue))")
    }

    func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) {
        loadedFeedForCurrentCheck = true
        recovery.reset()
        cancelRetry()
        record("Update feed loaded successfully")
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        availableVersion = nil
        isChecking = false
        status = "You’re up to date."
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        isChecking = false
        pendingInstall = nil
        installGeneration = UUID()
        record("Update aborted: \(error.localizedDescription)")
        if AppTerminationCoordinator.shared.updateShutdownPrepared {
            AppTerminationCoordinator.shared.cancelUpdateHandoff()
            ClashViewModel.shared.isToggling = false
        }
        if (error as NSError).code != 1001 { status = error.localizedDescription }
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        isChecking = false
        record("Update check finished (\(updateCheck.rawValue)), error: \(error.map { String(($0 as NSError).code) } ?? "none")")
        guard automaticallyChecks, !loadedFeedForCurrentCheck,
              let error, Self.isFeedRequestFailure(error) else { return }
        recovery.feedFailed(at: Date())
        scheduleRetry()
    }

    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem, untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        installGeneration = UUID()
        pendingInstall = installHandler
        resumeInstallation()
        return true
    }

    func updater(_ updater: SPUUpdater, willScheduleUpdateCheckAfterDelay delay: TimeInterval) {
        record("Automatic check scheduled in \(Int(delay)) seconds")
    }

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        record("Sparkle is terminating this process to relaunch the installed application")
    }

    private func record(_ message: String) {
        NSLog("[Ares Update] %@", message)
    }

    private static func isFeedRequestFailure(_ error: Error) -> Bool {
        let error = error as NSError
        if error.domain == SUSparkleErrorDomain {
            return [SUError.appcastError, .resumeAppcastError, .downloadError].contains { error.code == Int($0.rawValue) }
        }
        return error.domain == NSURLErrorDomain && error.code != NSURLErrorCancelled
    }

    private func startAutomaticRecovery() {
        guard controller != nil, pathMonitor == nil else { return }
        let monitor = NWPathMonitor()
        pathMonitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            let available = path.status == .satisfied
            Task { @MainActor [weak self] in self?.networkPathChanged(available: available) }
        }
        monitor.start(queue: DispatchQueue(label: "Ares.UpdatePath"))
        activeObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.resumeAutomaticSchedule() }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.resumeAutomaticSchedule() }
        }
    }

    private func stopAutomaticRecovery() {
        cancelRetry()
        recovery.reset()
        pathMonitor?.cancel()
        pathMonitor = nil
        pathWasAvailable = nil
        if let activeObserver { NotificationCenter.default.removeObserver(activeObserver) }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        activeObserver = nil
        wakeObserver = nil
    }

    private func networkPathChanged(available: Bool) {
        guard automaticallyChecks, pathMonitor != nil else { return }
        let restored = available && pathWasAvailable != true
        pathWasAvailable = available
        guard restored else { return }
        recovery.networkRestored(at: Date())
        resumeAutomaticSchedule()
    }

    private func resumeAutomaticSchedule() {
        guard automaticallyChecks, let updater = controller?.updater,
              !updater.sessionInProgress, !preparingInstall, pendingInstall == nil else { return }
        if recovery.retryAt != nil {
            scheduleRetry()
        } else if recovery.regularCheckIsOverdue(lastCheck: updater.lastUpdateCheckDate, now: Date()) {
            // Use Sparkle's scheduler for ordinary checks, including after wake.
            updater.resetUpdateCycle()
        }
    }

    private func cancelRetry() {
        retryTask?.cancel()
        retryTask = nil
    }

    private func scheduleRetry() {
        cancelRetry()
        guard automaticallyChecks, let deadline = recovery.retryAt else { return }
        let delay = max(0, deadline.timeIntervalSinceNow)
        record("Retrying failed update check in \(Int(delay.rounded(.up))) seconds")
        retryTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard let self, self.automaticallyChecks, let updater = self.controller?.updater,
                  !updater.sessionInProgress, updater.canCheckForUpdates,
                  !self.preparingInstall, self.pendingInstall == nil else { return }
            // One bounded recovery attempt, never a second periodic scheduler.
            updater.checkForUpdatesInBackground()
        }
    }

    private func resumeInstallation() {
        guard !preparingInstall, let install = pendingInstall else { return }
        preparingInstall = true
        let generation = installGeneration
        Task { @MainActor in
            defer { preparingInstall = false }
            let prepared = await AppTerminationCoordinator.shared.prepareForTermination()
            // Sparkle can abort while cleanup is awaiting an operation or authorization.
            // A stale install closure must never run after that abort.
            guard generation == installGeneration else {
                if prepared { AppTerminationCoordinator.shared.cancelUpdateHandoff() }
                return
            }
            guard prepared else {
                status = "Update is ready. Network cleanup failed; click the update dot to retry."
                canCheck = true
                AppState.shared.reportError(status)
                return
            }
            // Sparkle may bypass NSApplication's ordinary quit path. Explicit cleanup above
            // must succeed before allowing its installer to replace and relaunch the app.
            pendingInstall = nil
            // Keep runtime controls locked during the handoff to Sparkle.
            AppTerminationCoordinator.shared.updateShutdownPrepared = true
            ClashViewModel.shared.isToggling = true
            record("Network cleanup complete; handing installation and relaunch to Sparkle")
            install()
        }
    }
}
