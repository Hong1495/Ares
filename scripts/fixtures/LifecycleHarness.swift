import Foundation

@MainActor final class SceneAutomationService {
    static let shared = SceneAutomationService()
    func pause(reason: String) {}
}
enum ClashPorts { static let apiTun = 19097; static let apiNormal = 9097 }
@MainActor final class ClashViewModel {
    enum State { case ready, stopped; var isAPIReady: Bool { self == .ready } }
    var isToggling = false
    var runtimeState: State = .ready
    var isRunning = true
    enum Level { case debug }
    func addLog(_ text: String, level: Level) {}
}
@MainActor final class ClashController {
    var runtimeGeneration = UUID()
    var starts = 0, stops = 0, reads = 0
    var fail = false
    func startTrafficMonitor() { starts += 1 }
    func stopTrafficMonitor() { stops += 1 }
    func readRuntimeConfiguration() async throws -> Data {
        reads += 1
        if fail { throw URLError(.cannotConnectToHost) }
        return Data("{\"tun\":{\"enable\":false}}".utf8)
    }
}
extension Notification.Name {
    static let appDidWakeUp = Notification.Name("test-wake")
    static let appDidGoSilent = Notification.Name("test-silent")
}
@MainActor final class AppState {
    var systemIsSleeping = false
    var wakeVerificationTask: Task<Void, Never>?
    var isForeground = true, animationsEnabled = true, didSendInitialWake = false
    var operationStatus: String?
    var tunEnabled = false
    var syncs = 0, errors = 0
    let clashViewModel = ClashViewModel()
    let clashController = ClashController()
    func syncStatus() { syncs += 1 }
    func reportError(_ message: String) { errors += 1 }
}
@main struct Harness {
    @MainActor static func main() async {
        let app = AppState()
        app.systemWillSleep()
        precondition(app.systemIsSleeping && app.clashController.stops == 1)
        app.systemDidWake()
        await app.wakeVerificationTask?.value
        precondition(app.clashController.starts == 1 && app.syncs == 1 && app.errors == 0)
        app.isForeground = false
        app.systemDidWake()
        await app.wakeVerificationTask?.value
        precondition(app.clashController.starts == 1 && app.syncs == 2)
        app.clashViewModel.runtimeState = .stopped
        let reads = app.clashController.reads
        app.systemDidWake()
        await app.wakeVerificationTask?.value
        precondition(app.clashController.reads == reads)
        app.clashViewModel.runtimeState = .ready
        app.clashController.fail = true
        app.systemDidWake()
        await app.wakeVerificationTask?.value
        precondition(app.errors == 1 && app.clashController.starts == 1)
        app.systemDidWake()
        app.systemWillSleep()
        await app.wakeVerificationTask?.value
        precondition(app.errors == 1)
        print("PASS: sleep suspension, foreground/background wake, stopped-core preservation, failed readback, cancellation")
    }
}
