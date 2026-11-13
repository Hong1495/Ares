import Foundation

@MainActor final class AppState {
    static let shared = AppState()
    var systemIsSleeping = false, isPerformingNetworkOperation = false
}
@MainActor final class ClashViewModel {
    struct State { var isAPIReady = true }
    static let shared = ClashViewModel()
    var runtimeState = State(), isToggling = false, appliedProfileRevision = "r1"
}
@MainActor final class ProfileService {
    static let shared = ProfileService()
    var activeProfileID: UUID? = UUID(), activeProfileRevision = "r1"
}
@MainActor enum ScenarioService {
    struct Context { let revision: String; let settings: ScenarioSettings }
    struct Review { let target: ScenarioSettings; let sourceChanged: Bool }
    static let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ares-auto-" + UUID().uuidString)
    static var settings = ScenarioSettings(localRules: nil, dns: nil, policy: nil, egress: nil)
    static var calls = 0, fail = false
    static var beforeApply: (() -> Void)?
    static func context() throws -> Context { .init(revision: ProfileService.shared.activeProfileRevision, settings: settings) }
    static func matches(_ current: Context, defaults: UserDefaults) -> Bool { current.revision == ProfileService.shared.activeProfileRevision && current.settings == settings }
    static func review(_ scene: ManualScenario) throws -> Review { .init(target: scene.settings, sourceChanged: scene.sourceRevision != ProfileService.shared.activeProfileRevision) }
    static func apply(_ review: Review, automatic: Bool, stillValid: () -> Bool) async -> Bool {
        precondition(automatic); calls += 1; beforeApply?()
        guard stillValid(), !fail else { return false }
        settings = review.target; return true
    }
}
@main struct Harness {
    @MainActor static func main() async throws {
        let suite = "ares-auto-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: ScenarioService.directory) }
        let profile = ProfileService.shared.activeProfileID!
        var scene = try ManualScenario(name: "WiFi", profileID: profile, sourceRevision: "r1", settings: .init(localRules: "MATCH,DIRECT", dns: nil, policy: nil, egress: nil))
        scene.trigger = SceneTrigger(enabled: true, kind: "wifi", priority: 1)
        try ScenarioLibrary.save([scene], directory: ScenarioService.directory)
        let service = SceneAutomationService(defaults: defaults, monitorsNetwork: false)
        let wifi = SceneEnvironment(available: true, kind: "wifi", interface: "en0", expensive: false, constrained: false)
        service.receive(wifi)
        await service.evaluate(now: 0); await service.evaluate(now: 50)
        precondition(ScenarioService.calls == 0 && service.rows.count == 1) // Preview works without opt-in.
        service.setEnabled(true)
        await service.evaluate(now: 60); await service.evaluate(now: 69)
        precondition(ScenarioService.calls == 0)
        await service.evaluate(now: 70)
        precondition(ScenarioService.calls == 1 && ScenarioService.settings == scene.settings)
        await service.evaluate(now: 100)
        precondition(ScenarioService.calls == 1) // Matching settings do not restart the core.
        ScenarioService.settings.localRules = "manual edit"
        await service.evaluate(now: 101)
        precondition(service.paused)
        service.resume(); ScenarioService.fail = true
        await service.evaluate(now: 120); await service.evaluate(now: 130)
        precondition(service.paused && ScenarioService.calls == 2)
        await service.evaluate(now: 200)
        precondition(ScenarioService.calls == 2) // No failure retry loop.
        service.resume(); ScenarioService.fail = false
        AppState.shared.isPerformingNetworkOperation = true
        await service.evaluate(now: 210); await service.evaluate(now: 230)
        precondition(ScenarioService.calls == 2)
        AppState.shared.isPerformingNetworkOperation = false
        ClashViewModel.shared.runtimeState.isAPIReady = false
        await service.evaluate(now: 240)
        precondition(ScenarioService.calls == 2)
        ClashViewModel.shared.runtimeState.isAPIReady = true
        var duplicate = scene
        duplicate = try ManualScenario(name: "Conflict", profileID: profile, sourceRevision: "r1", settings: scene.settings)
        duplicate.trigger = scene.trigger
        try ScenarioLibrary.save([scene, duplicate], directory: ScenarioService.directory)
        await service.evaluate(now: 250); await service.evaluate(now: 280)
        precondition(ScenarioService.calls == 2 && service.status.contains("Conflicting"))
        try ScenarioLibrary.save([scene], directory: ScenarioService.directory)
        await service.evaluate(now: 290)
        service.receive(.unknown); await service.evaluate(now: 301)
        precondition(ScenarioService.calls == 2)
        service.receive(wifi); await service.evaluate(now: 310)
        ScenarioService.beforeApply = { service.receive(.unknown) }
        await service.evaluate(now: 320)
        precondition(service.paused && ScenarioService.calls == 3 && ScenarioService.settings.localRules == "manual edit")
        ScenarioService.beforeApply = nil
        service.resume(); service.receive(wifi)
        ProfileService.shared.activeProfileRevision = "r2"; ClashViewModel.shared.appliedProfileRevision = "r2"
        await service.evaluate(now: 340); await service.evaluate(now: 360)
        precondition(ScenarioService.calls == 3 && service.status.contains("Subscription changed"))
        service.pause()
        let reloaded = SceneAutomationService(defaults: defaults, monitorsNetwork: false)
        precondition(reloaded.enabled && reloaded.paused)
        print("PASS: production automation opt-in, match preview, debounce, idempotence, conflicts, busy/stopped guards, manual edits, failure latch, environment race, revision guard and persistent pause")
    }
}
