import Foundation
import SubscriptionKit

@MainActor enum ScenarioService {
    struct Context {
        let profileID: UUID
        let revision: String
        let settings: ScenarioSettings
        var storedMode: String? = nil
        var strictSelections = false
    }
    struct Review: Identifiable {
        let id = UUID()
        let name: String
        let context: Context
        let target: ScenarioSettings
        let sourceChanged: Bool
        let isUndo: Bool
        var scene: ManualScenario? = nil
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
    static func history() throws -> [SceneExecution] { try SceneExecutionHistory.load(directory: directory) }
    static func context(defaults: UserDefaults = .standard) throws -> Context {
        let profiles = ProfileService.shared
        guard let id = profiles.activeProfileID else { throw URLError(.fileDoesNotExist) }
        var settings = ScenarioSettings.capture(profile: id, defaults: defaults)
        settings.mode = defaults.string(forKey: DefaultsKeys.clashMode) ?? "rule"
        settings.selections = profiles.savedSelections()
        return Context(profileID: id, revision: profiles.activeProfileRevision, settings: settings,
                       storedMode: defaults.string(forKey: DefaultsKeys.clashMode),
                       strictSelections: defaults.bool(forKey: "sceneStrictSelections." + id.uuidString))
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
    static func update(_ original: ManualScenario, name: String, settings: ScenarioSettings,
                       expected: Context, trigger: SceneTrigger? = nil, defaults: UserDefaults = .standard, storage: URL? = nil) throws {
        guard original.profileID == expected.profileID, matches(expected, defaults: defaults) else { throw CancellationError() }
        try validate(settings)
        var edited = try original.edited(name: name, settings: settings)
        if edited.settings != original.settings { edited.validatedRevision = nil }
        edited.trigger = trigger
        try trigger?.validate()
        try ScenarioLibrary.replace(original, with: edited, directory: storage ?? directory)
    }
    static func review(_ scenario: ManualScenario, defaults: UserDefaults = .standard) throws -> Review {
        let current = try context(defaults: defaults)
        guard scenario.profileID == current.profileID else { throw CancellationError() }
        return Review(name: scenario.name, context: current, target: scenario.settings.resolvingRouting(from: current.settings),
            sourceChanged: (scenario.validatedRevision ?? scenario.sourceRevision) != current.revision, isUndo: false, scene: scenario)
    }
    static func undoReview(defaults: UserDefaults = .standard) -> Review? {
        guard let undo, let current = try? context(defaults: defaults), current.profileID == undo.context.profileID,
              current.revision == undo.context.revision, current.settings == undo.applied else { return nil }
        return Review(name: "Undo Last Switch", context: current, target: undo.context.settings, sourceChanged: false, isUndo: true)
    }
    static func matches(_ context: Context, defaults: UserDefaults) -> Bool {
        guard let current = try? self.context(defaults: defaults) else { return false }
        return current.profileID == context.profileID && current.revision == context.revision &&
            current.settings == context.settings && current.storedMode == context.storedMode && current.strictSelections == context.strictSelections
    }
    static func apply(_ review: Review, defaults: UserDefaults = .standard, storage: URL? = nil, automatic: Bool = false, stillValid: () -> Bool = { true }) async -> Bool {
        let app = AppState.shared, vm = ClashViewModel.shared
        var result = "Not applied"
        defer {
            let entry = SceneExecution(sceneID: review.scene?.id, name: review.name, automatic: automatic,
                                       result: result, sections: review.changes.map(\.id))
            do { try SceneExecutionHistory.append(entry, directory: storage ?? directory) }
            catch { app.reportError("Scene result: \(result). Execution history could not be saved; existing history was retained.") }
        }
        func sceneIsCurrent() -> Bool {
            guard let scene = review.scene else { return true }
            return (try? ScenarioLibrary.load(directory: storage ?? directory).contains(scene)) == true
        }
        guard stillValid(), matches(review.context, defaults: defaults) else {
            app.reportError("Settings or subscription changed after review. Review the scene again."); return false
        }
        guard sceneIsCurrent() else {
            app.reportError("This scene changed or was deleted after review. Reload and review it again."); return false
        }
        do { try validate(review.target) }
        catch { app.reportError("The scene contains invalid overrides. No settings were changed."); return false }
        guard !vm.isToggling, app.beginOperation("Applying Scene") else { result = "Busy · Not applied"; return false }
        vm.isToggling = true
        defer { vm.isToggling = false; app.finishOperation(error: app.lastOperationError) }
        let target = review.target.resolvingRouting(from: review.context.settings)
        let includesSelections = review.scene.map { $0.settings.selections != nil } ?? (review.target.selections != nil)
        let includesMode = review.scene.map { $0.settings.mode != nil } ?? (review.target.mode != nil)
        func install() {
            target.install(profile: review.context.profileID, defaults: defaults)
            if review.isUndo, let original = undo?.context {
                if let mode = original.storedMode { defaults.set(mode, forKey: DefaultsKeys.clashMode) }
                else { defaults.removeObject(forKey: DefaultsKeys.clashMode) }
            } else if includesMode, let mode = target.mode { defaults.set(mode, forKey: DefaultsKeys.clashMode) }
            if includesSelections, let choices = target.selections {
                ProfileService.shared.replaceSavedSelections(choices, profile: review.context.profileID, defaults: defaults)
                defaults.set(review.isUndo ? (undo?.context.strictSelections ?? false) : true, forKey: "sceneStrictSelections." + review.context.profileID.uuidString)
            }
        }
        func restore() {
            review.context.settings.install(profile: review.context.profileID, defaults: defaults)
            defaults.set(review.context.strictSelections, forKey: "sceneStrictSelections." + review.context.profileID.uuidString)
            if let mode = review.context.storedMode { defaults.set(mode, forKey: DefaultsKeys.clashMode) }
            else { defaults.removeObject(forKey: DefaultsKeys.clashMode) }
            ProfileService.shared.replaceSavedSelections(review.context.settings.selections ?? [:], profile: review.context.profileID, defaults: defaults)
            app.currentMode = ClashConfig.Mode(rawValue: review.context.settings.mode ?? "rule") ?? .rule
        }
        if vm.runtimeState.isAPIReady {
            do {
                let checkpoint = try await vm.captureRecoveryCheckpoint()
                guard stillValid(), matches(review.context, defaults: defaults), sceneIsCurrent() else { throw CancellationError() }
                let outcome = await ConfigurationCoordinator.replace(previous: checkpoint, targetMode: app.tunEnabled,
                    restoreProxy: app.systemProxyEnabled, preparePreferences: { install() }, restorePreferences: { restore() }, verify: {
                        guard stillValid(), sceneIsCurrent() else { throw CancellationError() }
                        if includesSelections, let choices = target.selections { try await ProfileService.shared.verifySceneSelections(choices) }
                        guard stillValid() else { throw CancellationError() }
                    }, beforeStop: {
                        guard stillValid(), sceneIsCurrent() else { throw CancellationError() }
                    })
                guard outcome == .committed else {
                    result = "Failed · \(outcome)"
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
        result = vm.runtimeState.isAPIReady ? "Applied and verified" : "Saved · Awaiting runtime verification"
        // Only a successful running-core transaction can migrate a scene to a new subscription revision.
        if vm.runtimeState.isAPIReady, let scene = review.scene, review.sourceChanged {
            var migrated = scene
            migrated.validatedRevision = review.context.revision
            do { try ScenarioLibrary.replace(scene, with: migrated, directory: storage ?? directory) }
            catch { app.reportError("Scene applied, but migration approval could not be saved. Automatic switching remains blocked.") }
        }
        app.currentMode = ClashConfig.Mode(rawValue: target.mode ?? "rule") ?? .rule
        undo = review.isUndo ? nil : Undo(context: review.context, applied: target)
        if !automatic { NotificationCenter.default.post(name: .sceneManuallyApplied, object: nil) }
        return true
    }
    private static func validate(_ settings: ScenarioSettings) throws {
        if let mode = settings.mode, !["rule", "global", "direct"].contains(mode) { throw ScenarioLibrary.Failure.invalid }
        if let choices = settings.selections, choices.contains(where: { $0.key.isEmpty || $0.value.isEmpty }) { throw ScenarioLibrary.Failure.invalid }
        if let dns = settings.dns { _ = try DNSConfiguration.apply(source: "{}", overrides: dns) }
        if let policy = settings.policy { _ = try PolicyConfiguration.decodeOverrides(policy) }
        if let egress = settings.egress { _ = try EgressConfiguration.decode(egress) }
        // Cross-field/rule/target semantics are validated on the fully generated candidate by mihomo.
    }
}
