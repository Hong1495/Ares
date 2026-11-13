import Foundation
import SubscriptionKit

@MainActor enum ScenarioService {
    struct Context {
        let profileID: UUID
        let revision: String
        let settings: ScenarioSettings
    }
    struct Review: Identifiable {
        let id = UUID()
        let name: String
        let context: Context
        let target: ScenarioSettings
        let sourceChanged: Bool
        let isUndo: Bool
        var changes: [ScenarioSettings.Difference] { target.differences(from: context.settings) }
    }
    private struct Undo {
        let context: Context
        let applied: ScenarioSettings
    }
    private static var undo: Undo?
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Ares/scenarios")
    }
    static func context(defaults: UserDefaults = .standard) throws -> Context {
        let profiles = ProfileService.shared
        guard let id = profiles.activeProfileID else { throw URLError(.fileDoesNotExist) }
        return Context(profileID: id, revision: profiles.activeProfileRevision, settings: .capture(profile: id, defaults: defaults))
    }
    static func list() throws -> [ManualScenario] {
        let id = try context().profileID
        return try ScenarioLibrary.load(directory: directory).filter { $0.profileID == id }
    }
    static func save(name: String, expected: Context, defaults: UserDefaults = .standard) throws {
        guard matches(expected, defaults: defaults) else { throw CancellationError() }
        try validate(expected.settings)
        let scenario = try ManualScenario(name: name, profileID: expected.profileID, sourceRevision: expected.revision, settings: expected.settings)
        var library = try ScenarioLibrary.load(directory: directory)
        library.append(scenario)
        try ScenarioLibrary.save(library, directory: directory)
    }
    static func remove(_ scenario: ManualScenario) throws {
        var library = try ScenarioLibrary.load(directory: directory)
        guard library.contains(scenario) else { throw CancellationError() }
        library.removeAll { $0.id == scenario.id }
        try ScenarioLibrary.save(library, directory: directory)
    }
    static func review(_ scenario: ManualScenario, defaults: UserDefaults = .standard) throws -> Review {
        let current = try context(defaults: defaults)
        guard scenario.profileID == current.profileID else { throw CancellationError() }
        return Review(name: scenario.name, context: current, target: scenario.settings,
            sourceChanged: scenario.sourceRevision != current.revision, isUndo: false)
    }
    static func undoReview(defaults: UserDefaults = .standard) -> Review? {
        guard let undo, let current = try? context(defaults: defaults), current.profileID == undo.context.profileID,
              current.revision == undo.context.revision, current.settings == undo.applied else { return nil }
        return Review(name: "Undo Last Switch", context: current, target: undo.context.settings, sourceChanged: false, isUndo: true)
    }
    static func matches(_ context: Context, defaults: UserDefaults) -> Bool {
        ProfileService.shared.activeProfileID == context.profileID && ProfileService.shared.activeProfileRevision == context.revision &&
            ScenarioSettings.capture(profile: context.profileID, defaults: defaults) == context.settings
    }
    static func apply(_ review: Review, defaults: UserDefaults = .standard) async -> Bool {
        let app = AppState.shared, vm = ClashViewModel.shared
        guard matches(review.context, defaults: defaults) else {
            app.reportError("Settings or subscription changed after review. Review the scene again."); return false
        }
        do { try validate(review.target) }
        catch { app.reportError("The scene contains invalid overrides. No settings were changed."); return false }
        guard !vm.isToggling, app.beginOperation("Applying Scene") else { return false }
        vm.isToggling = true
        defer { vm.isToggling = false; app.finishOperation(error: app.lastOperationError) }
        func install() { review.target.install(profile: review.context.profileID, defaults: defaults) }
        func restore() { review.context.settings.install(profile: review.context.profileID, defaults: defaults) }
        if vm.runtimeState.isAPIReady {
            do {
                let checkpoint = try await vm.captureRecoveryCheckpoint()
                guard matches(review.context, defaults: defaults) else { throw CancellationError() }
                let outcome = await ConfigurationCoordinator.replace(previous: checkpoint, targetMode: app.tunEnabled,
                    restoreProxy: app.systemProxyEnabled, preparePreferences: { install() }, restorePreferences: { restore() })
                guard outcome == .committed else {
                    restore(); app.reportError("Scene switch failed (\(outcome)). Check the runtime status before retrying."); return false
                }
            } catch { app.reportError("The current runtime could not be captured. No scene settings were changed."); return false }
        } else {
            guard vm.runtimeState == .stopped else { app.reportError("Wait for a stable core state before switching scenes."); return false }
            install()
            do {
                try await ConfigService.shared.buildConfig(tunEnabled: app.tunEnabled)
                guard ProfileService.shared.activeProfileRevision == review.context.revision else { throw CancellationError() }
            } catch { restore(); app.reportError("Scene validation failed. Previous settings were retained."); return false }
        }
        undo = review.isUndo ? nil : Undo(context: review.context, applied: review.target)
        return true
    }
    private static func validate(_ settings: ScenarioSettings) throws {
        if let dns = settings.dns { _ = try DNSConfiguration.apply(source: "{}", overrides: dns) }
        if let policy = settings.policy { _ = try PolicyConfiguration.decodeOverrides(policy) }
        if let egress = settings.egress { _ = try EgressConfiguration.decode(egress) }
        // Cross-field/rule/target semantics are validated on the fully generated candidate by mihomo.
    }
}
