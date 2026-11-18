import AppKit
import Sparkle

// Explicit inert substitutes: production lifecycle/proxy/core code is never linked.
@MainActor final class AppTerminationCoordinator {
    static let shared = AppTerminationCoordinator()
    var updateShutdownPrepared = false
    func cancelUpdateHandoff() { updateShutdownPrepared = false }
    func prepareForTermination() async -> Bool { fatalError("Installation is forbidden in updater tests") }
}
@MainActor final class ClashViewModel {
    static let shared = ClashViewModel()
    var isToggling = false
}
@MainActor final class AppState {
    static let shared = AppState()
    func reportError(_ message: String) { fatalError(message) }
}

@MainActor final class UpdateHarness: NSObject, NSApplicationDelegate {
    let updates = AppUpdateService(recovery: AppUpdateRecovery(retryDelays: [0.25, 0.5, 0.75]))
    let disableAfterFailure = CommandLine.arguments.contains("--disable")
    let initiallyOff = CommandLine.arguments.contains("--off")
    var timer: Timer?
    var disabled = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        updates.automaticallyChecks = !initiallyOff
        updates.start()
        precondition(updates.isConfigured)
        let started = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [self] _ in
            MainActor.assumeIsolated {
                if disableAfterFailure, !disabled, !updates.status.isEmpty {
                    updates.automaticallyChecks = false
                    disabled = true
                    print("AUTOMATIC CHECKS DISABLED")
                }
                if Date().timeIntervalSince(started) > 4 {
                    precondition(updates.availableVersion == nil)
                    precondition(!updates.isChecking)
                    precondition(!disableAfterFailure || disabled)
                    print("HARNESS COMPLETE")
                    fflush(stdout)
                    UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
                    exit(0)
                }
            }
        }
    }
}

@main struct AppUpdateHarnessMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let delegate = UpdateHarness()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
