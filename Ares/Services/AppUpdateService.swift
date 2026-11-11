import AppKit
import Combine
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
        }
    }
    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    private var controller: SPUStandardUpdaterController?
    private var pendingInstall: (() -> Void)?
    private var preparingInstall = false
    private var canCheckObservation: NSKeyValueObservation?
    @Published private(set) var canCheck = false

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
        } catch {
            status = error.localizedDescription
            self.controller = nil
        }
    }

    func checkForUpdates() {
        if controller == nil { start() }
        guard let controller, !preparingInstall else { return }
        if pendingInstall != nil { resumeInstallation(); return }
        guard controller.updater.canCheckForUpdates else { return }
        // Bringing an existing update window into focus does not start a new check.
        if controller.updater.sessionInProgress {
            controller.checkForUpdates(nil)
            return
        }
        guard !isChecking else { return }
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
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        availableVersion = nil
        isChecking = false
        status = "You’re up to date."
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        isChecking = false
        if AppTerminationCoordinator.shared.updateShutdownPrepared {
            AppTerminationCoordinator.shared.updateShutdownPrepared = false
            ClashViewModel.shared.isToggling = false
        }
        if (error as NSError).code != 1001 { status = error.localizedDescription }
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        isChecking = false
    }

    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem, untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        pendingInstall = installHandler
        resumeInstallation()
        return true
    }

    private func resumeInstallation() {
        guard !preparingInstall, let install = pendingInstall else { return }
        preparingInstall = true
        Task { @MainActor in
            defer { preparingInstall = false }
            guard await AppTerminationCoordinator.shared.prepareForTermination() else {
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
            install()
        }
    }
}
