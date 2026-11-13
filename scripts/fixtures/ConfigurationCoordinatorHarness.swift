import Foundation
import SubscriptionKit

@MainActor final class Trace {
    static let shared = Trace()
    var events: [String] = []
    var starts: [Bool] = []
    var stops: [Bool] = []
    var buildFails = false
    var restoreFails = false
    var captureFails = false
    var checkpointMissing = false
    var proxyResults: [Bool] = []
    func reset() { events = []; starts = []; stops = []; buildFails = false; restoreFails = false; captureFails = false; checkpointMissing = false; proxyResults = [] }
}
@MainActor final class AppState {
    static let shared = AppState()
    var currentMode = ClashConfig.Mode.rule
    var tunEnabled = false, systemProxyEnabled = true
    var busy = false
    var lastOperationError: String?
    func beginOperation(_ text: String) -> Bool { if busy { return false }; busy = true; return true }
    func finishOperation(error: String? = nil) { busy = false }
    func reportError(_ text: String) { Trace.shared.events.append("error") }
    func enableSystemProxy(expectedRevision: String?) async -> Bool {
        Trace.shared.events.append("proxy:" + (expectedRevision ?? "current"))
        return Trace.shared.proxyResults.isEmpty ? true : Trace.shared.proxyResults.removeFirst()
    }
}
@MainActor final class ProfileService {
    static let shared = ProfileService()
    var choices: [String: String] = [:]
    var selectionsFail = false
    func savedSelections() -> [String: String] { choices }
    func replaceSavedSelections(_ choices: [String: String], profile: UUID, defaults: UserDefaults) { self.choices = choices }
    func verifySceneSelections(_ choices: [String: String]) async throws {
        Trace.shared.events.append("selections")
        if selectionsFail { throw URLError(.cannotParseResponse) }
    }
    var activeProfileRevision = "new"
    var activeProfileID: UUID?
    struct Profile { let path: URL }
    var activeProfile: Profile?
}
@MainActor final class NetworkMITMService {
    static let shared = NetworkMITMService()
    var isRunning = true
    func updateUpstream(tunEnabled: Bool) async -> Bool { Trace.shared.events.append("upstream"); return true }
}
@MainActor final class ConfigService {
    static let shared = ConfigService()
    func policyGroups(profilePath: URL, overrides: String) async throws -> ([PolicyConfiguration.Group], [PolicyConfiguration.Group]) { ([], []) }
    func dnsSettings(profilePath: URL, overrides: String) async throws -> ([String: String], [String: String], [String: String]) { ([:], [:], [:]) }
    func egressSettings(profilePath: URL, overrides: String) async throws -> (EgressConfiguration.Document, EgressConfiguration.Document) {
        let document = try EgressConfiguration.read("{}"); return (document, document)
    }
    var content = "old"
    var checkpoint = RuntimeCheckpoint(configuration: "old", profileID: nil, profileRevision: "old", selections: [:], tunEnabled: false)
    func buildConfig(tunEnabled: Bool) async throws {
        Trace.shared.events.append("prepare")
        if Trace.shared.buildFails { throw URLError(.cannotParseResponse) }
        content = "new"
    }
    func savedConfiguration(tunEnabled: Bool) async throws -> String { content }
    func restoreConfiguration(_ text: String, tunEnabled: Bool) async throws {
        Trace.shared.events.append("file:" + text)
        if Trace.shared.restoreFails { throw URLError(.cannotWriteToFile) }
        content = text
    }
    func successfulRuntime(tunEnabled: Bool) async throws -> RuntimeCheckpoint {
        if Trace.shared.checkpointMissing { throw URLError(.fileDoesNotExist) }
        return checkpoint
    }
}
@MainActor final class ClashViewModel {
    static let shared = ClashViewModel()
    struct State: Equatable {
        var isAPIReady = true
        static let stopped = State(isAPIReady: false)
    }
    var isRunning: Bool { runtimeState.isAPIReady }
    var runtimeState = State()
    var isToggling = false
    var appliedProfileRevision = "new"
    func captureRecoveryCheckpoint() async throws -> RuntimeCheckpoint {
        Trace.shared.events.append("capture")
        if Trace.shared.captureFails { throw URLError(.cannotParseResponse) }
        return RuntimeCheckpoint(configuration: "current", profileID: nil, profileRevision: "current", selections: [:], tunEnabled: false)
    }
    func startCore(isRestart: Bool, preparedConfiguration: String?, recovery: RuntimeCheckpoint?, persistCheckpoint: Bool) async {
        precondition(!persistCheckpoint)
        Trace.shared.events.append("start:" + (recovery?.configuration ?? preparedConfiguration ?? "generated"))
        runtimeState.isAPIReady = Trace.shared.starts.isEmpty ? true : Trace.shared.starts.removeFirst()
    }
    func stopCore(intendedRestart: Bool) async -> Bool {
        Trace.shared.events.append("stop")
        runtimeState.isAPIReady = false
        return Trace.shared.stops.isEmpty ? true : Trace.shared.stops.removeFirst()
    }
    func persistActiveCheckpoint() async { Trace.shared.events.append("checkpoint") }
}
@main struct Harness {
    @MainActor static func main() async {
        let historyDir = FileManager.default.temporaryDirectory.appendingPathComponent("ares-history-harness-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: historyDir) }
        let trace = Trace.shared
        let old = ConfigService.shared.checkpoint
        func run() async -> ConfigurationTransition.Outcome {
            await ConfigurationCoordinator.replace(previous: old, targetMode: true, restoreProxy: true,
                preparePreferences: { trace.events.append("preferences:new") },
                activatePreferences: { trace.events.append("mode:new") },
                restorePreferences: { trace.events.append("preferences:old") })
        }
        trace.reset()
        var outcome = await run()
        precondition(outcome == .committed)
        precondition(trace.events == ["preferences:new", "prepare", "stop", "mode:new", "start:new", "upstream", "proxy:current", "checkpoint"])
        trace.reset(); trace.starts = [false, true]
        outcome = await run()
        precondition(outcome == .restored)
        precondition(trace.events.suffix(5) == ["preferences:old", "start:old", "upstream", "proxy:old", "checkpoint"])
        trace.reset(); trace.proxyResults = [false, true]
        outcome = await run()
        precondition(outcome == .restored)
        precondition(trace.events.filter { $0 == "checkpoint" }.count == 1)
        trace.reset(); trace.stops = [false]
        outcome = await run()
        precondition(outcome == .unchanged && !trace.events.contains(where: { $0.hasPrefix("start:") }))
        trace.reset(); trace.buildFails = true
        outcome = await run()
        precondition(outcome == .preparationFailed && !trace.events.contains("stop"))
        trace.reset(); trace.starts = [false]; trace.stops = [true, false]
        outcome = await run()
        precondition(outcome == .recoveryRequired && !trace.events.contains("start:old"))
        trace.reset(); trace.buildFails = true; trace.restoreFails = true
        outcome = await run()
        precondition(outcome == .recoveryRequired)
        func resetRecovery() {
            trace.reset()
            ClashViewModel.shared.runtimeState.isAPIReady = true
            ProfileService.shared.activeProfileID = nil
            AppState.shared.busy = false
        }
        for scenario in ["missing", "profile", "capture", "validation", "stop", "success", "cold", "rollback", "cleanup", "proxy"] {
            resetRecovery()
            switch scenario {
            case "missing": trace.checkpointMissing = true
            case "profile": ProfileService.shared.activeProfileID = UUID()
            case "capture": trace.captureFails = true
            case "validation": trace.restoreFails = true
            case "stop": trace.stops = [false]
            case "cold": ClashViewModel.shared.runtimeState.isAPIReady = false
            case "rollback": trace.starts = [false, true]
            case "cleanup": trace.starts = [false]; trace.stops = [true, false]
            case "proxy": trace.proxyResults = [false, true]
            default: break
            }
            let restored = await ConfigurationCoordinator.restoreLastSuccessful()
            precondition(restored == ["success", "cold"].contains(scenario), scenario)
            precondition(!AppState.shared.busy && !ClashViewModel.shared.isToggling)
            switch scenario {
            case "missing", "profile", "capture", "validation": precondition(!trace.events.contains("stop"))
            case "stop": precondition(trace.events.contains("file:current") && !trace.events.contains("start:old"))
            case "rollback", "proxy": precondition(trace.events.contains("start:current") && trace.events.filter { $0 == "checkpoint" }.count == 1)
            case "cleanup": precondition(!trace.events.contains("start:current"))
            default: precondition(trace.events.last == "checkpoint")
            }
        }
        let suite = "ares-rules-harness-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        for scenario in ["success", "validation", "rollback", "failed-cleanup", "stopped", "stopped-invalid", "revision"] {
            resetRecovery()
            defaults.removeObject(forKey: DefaultsKeys.localRules)
            switch scenario {
            case "validation": trace.buildFails = true
            case "rollback": trace.starts = [false, true]
            case "failed-cleanup": trace.starts = [false]; trace.stops = [true, false]
            case "stopped": ClashViewModel.shared.runtimeState = .stopped
            case "stopped-invalid": ClashViewModel.shared.runtimeState = .stopped; trace.buildFails = true
            default: break
            }
            let applied = await LocalRulesService.apply("MATCH,DIRECT", expectedRevision: scenario == "revision" ? "stale" : "new", defaults: defaults)
            precondition(applied == ["success", "stopped"].contains(scenario), scenario)
            precondition((defaults.string(forKey: DefaultsKeys.localRules) == "MATCH,DIRECT") == applied)
            precondition(!AppState.shared.busy && !ClashViewModel.shared.isToggling)
            if scenario.hasPrefix("stopped") || scenario == "revision" { precondition(!trace.events.contains("stop")) }
        }
        resetRecovery()
        defaults.set("MATCH,REJECT", forKey: DefaultsKeys.localRules)
        let staleRules = await LocalRulesService.apply("MATCH,DIRECT", expectedRevision: "new", expectedRules: "", defaults: defaults)
        precondition(!staleRules && defaults.string(forKey: DefaultsKeys.localRules) == "MATCH,REJECT")
        precondition(!trace.events.contains("prepare") && !trace.events.contains("stop"))
        let policyKey = PolicyGroupService.key(UUID())
        for scenario in ["success", "validation", "rollback", "cleanup", "stale", "stopped", "stopped-invalid"] {
            resetRecovery()
            defaults.removeObject(forKey: policyKey)
            let snapshot = PolicyGroupService.Snapshot(revision: "new", storageKey: policyKey, stored: "{}", inherited: [], effective: [])
            switch scenario {
            case "validation": trace.buildFails = true
            case "rollback": trace.starts = [false, true]
            case "cleanup": trace.starts = [false]; trace.stops = [true, false]
            case "stale": defaults.set("changed", forKey: policyKey)
            case "stopped": ClashViewModel.shared.runtimeState = .stopped
            case "stopped-invalid": ClashViewModel.shared.runtimeState = .stopped; trace.buildFails = true
            default: break
            }
            let success = await PolicyGroupService.apply(#"{"Auto":{"interval":"300"}}"#, snapshot: snapshot, defaults: defaults)
            precondition(success == ["success", "stopped"].contains(scenario))
            if !success { precondition(defaults.string(forKey: policyKey) == (scenario == "stale" ? "changed" : nil)) }
            precondition(!AppState.shared.busy && !ClashViewModel.shared.isToggling)
        }
        let dnsKey = DNSSettingsService.key(UUID())
        for scenario in ["success", "validation", "rollback", "cleanup", "stale", "stopped", "stopped-invalid"] {
            resetRecovery()
            defaults.removeObject(forKey: dnsKey)
            let snapshot = DNSSettingsService.Snapshot(revision: "new", storageKey: dnsKey, stored: "{}", inherited: [:], effective: [:], sources: [:])
            switch scenario {
            case "validation": trace.buildFails = true
            case "rollback": trace.starts = [false, true]
            case "cleanup": trace.starts = [false]; trace.stops = [true, false]
            case "stale": defaults.set("changed", forKey: dnsKey)
            case "stopped": ClashViewModel.shared.runtimeState = .stopped
            case "stopped-invalid": ClashViewModel.shared.runtimeState = .stopped; trace.buildFails = true
            default: break
            }
            let success = await DNSSettingsService.apply(#"{"respect-rules":"false"}"#, snapshot: snapshot, defaults: defaults)
            precondition(success == ["success", "stopped"].contains(scenario))
            if !success { precondition(defaults.string(forKey: dnsKey) == (scenario == "stale" ? "changed" : nil)) }
            precondition(!AppState.shared.busy && !ClashViewModel.shared.isToggling)
        }
        let egressKey = EgressSettingsService.key(UUID())
        for scenario in ["success", "validation", "rollback", "cleanup", "stale", "stopped", "stopped-invalid"] {
            resetRecovery()
            defaults.removeObject(forKey: egressKey)
            let snapshot = EgressSettingsService.Snapshot(revision: "new", storageKey: egressKey, stored: EgressConfiguration.empty, inherited: try! EgressConfiguration.read("{}"), effective: try! EgressConfiguration.read("{}"))
            switch scenario {
            case "validation": trace.buildFails = true
            case "rollback": trace.starts = [false, true]
            case "cleanup": trace.starts = [false]; trace.stops = [true, false]
            case "stale": defaults.set("changed", forKey: egressKey)
            case "stopped": ClashViewModel.shared.runtimeState = .stopped
            case "stopped-invalid": ClashViewModel.shared.runtimeState = .stopped; trace.buildFails = true
            default: break
            }
            let success = await EgressSettingsService.apply(#"{"nodes":{},"interface":"lo0"}"#, snapshot: snapshot, defaults: defaults)
            precondition(success == ["success", "stopped"].contains(scenario))
            if !success { precondition(defaults.string(forKey: egressKey) == (scenario == "stale" ? "changed" : nil)) }
            precondition(!AppState.shared.busy && !ClashViewModel.shared.isToggling)
        }
        let sceneProfile = UUID()
        ProfileService.shared.activeProfileID = sceneProfile
        let originalScene = ScenarioSettings(localRules: nil, dns: nil, policy: nil, egress: nil)
        let nextScene = ScenarioSettings(localRules: "MATCH,DIRECT", dns: "{}", policy: "{}", egress: EgressConfiguration.empty)
        for scenario in ["success", "validation", "rollback", "cleanup", "stale", "stopped", "stopped-invalid", "profile"] {
            resetRecovery()
            ProfileService.shared.activeProfileID = sceneProfile
            originalScene.install(profile: sceneProfile, defaults: defaults)
            let context = try! ScenarioService.context(defaults: defaults)
            let review = ScenarioService.Review(name: "Test", context: context, target: nextScene, sourceChanged: false, isUndo: false)
            switch scenario {
            case "validation": trace.buildFails = true
            case "rollback": trace.starts = [false, true]
            case "cleanup": trace.starts = [false]; trace.stops = [true, false]
            case "stale": defaults.set("changed", forKey: "localRules")
            case "profile": ProfileService.shared.activeProfileID = UUID()
            case "stopped": ClashViewModel.shared.runtimeState = .stopped
            case "stopped-invalid": ClashViewModel.shared.runtimeState = .stopped; trace.buildFails = true
            default: break
            }
            let success = await ScenarioService.apply(review, defaults: defaults, storage: historyDir)
            precondition(success == ["success", "stopped"].contains(scenario))
            if success {
                precondition(ScenarioSettings.capture(profile: sceneProfile, defaults: defaults) == nextScene)
                let undo = ScenarioService.undoReview(defaults: defaults)!
                let undone = await ScenarioService.apply(undo, defaults: defaults, storage: historyDir)
                precondition(undone)
                precondition(ScenarioSettings.capture(profile: sceneProfile, defaults: defaults) == originalScene)
                precondition(ScenarioService.undoReview(defaults: defaults) == nil)
            } else if scenario != "stale" {
                precondition(ScenarioSettings.capture(profile: sceneProfile, defaults: defaults) == originalScene)
            }
            precondition(!AppState.shared.busy && !ClashViewModel.shared.isToggling)
        }
        resetRecovery()
        ProfileService.shared.activeProfileID = sceneProfile
        originalScene.install(profile: sceneProfile, defaults: defaults)
        let initial = try! ScenarioService.context(defaults: defaults)
        let first = ScenarioService.Review(name: "Office", context: initial, target: nextScene, sourceChanged: false, isUndo: false)
        let switched = await ScenarioService.apply(first, defaults: defaults, storage: historyDir)
        precondition(switched && ScenarioService.undoReview(defaults: defaults) != nil)
        defaults.set("newer edit", forKey: "localRules")
        precondition(ScenarioService.undoReview(defaults: defaults) == nil)
        nextScene.install(profile: sceneProfile, defaults: defaults)
        ProfileService.shared.activeProfileRevision = "updated subscription"
        precondition(ScenarioService.undoReview(defaults: defaults) == nil)
        let scene = try! ManualScenario(name: "Office", profileID: sceneProfile, sourceRevision: "new", settings: nextScene)
        precondition((try! ScenarioService.review(scene, defaults: defaults)).sourceChanged)

        let sceneDir = FileManager.default.temporaryDirectory.appendingPathComponent("ares-editor-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: sceneDir) }
        try! ScenarioLibrary.save([scene], directory: sceneDir)
        let editorContext = try! ScenarioService.context(defaults: defaults)
        trace.reset()
        try! ScenarioService.update(scene, name: "Edited", settings: originalScene, expected: editorContext, defaults: defaults, storage: sceneDir)
        precondition(ScenarioSettings.capture(profile: sceneProfile, defaults: defaults) == nextScene)
        precondition(trace.events.isEmpty) // Saving a draft must not touch the core or live preferences.
        let editedScene = try! ScenarioLibrary.load(directory: sceneDir)[0]
        do {
            try ScenarioService.update(scene, name: "Stale", settings: nextScene, expected: editorContext, defaults: defaults, storage: sceneDir)
            preconditionFailure("stale scene replaced")
        } catch {}
        defaults.set("external edit", forKey: "localRules")
        do {
            try ScenarioService.update(editedScene, name: "Stale context", settings: nextScene, expected: editorContext, defaults: defaults, storage: sceneDir)
            preconditionFailure("stale settings accepted")
        } catch {}
        precondition(try! ScenarioLibrary.load(directory: sceneDir) == [editedScene])
        precondition(trace.events.isEmpty)
        nextScene.install(profile: sceneProfile, defaults: defaults)
        let staleSceneReview = ScenarioService.Review(name: scene.name, context: editorContext, target: scene.settings, sourceChanged: true, isUndo: false, scene: scene)
        let staleApplied = await ScenarioService.apply(staleSceneReview, defaults: defaults, storage: sceneDir)
        precondition(!staleApplied && !trace.events.contains("prepare") && !trace.events.contains("stop"))
        precondition(ScenarioSettings.capture(profile: sceneProfile, defaults: defaults) == nextScene)

        // Mode and node choices participate in commit, rollback, undo and stale review rejection.
        for failure in [false, true] {
            resetRecovery(); ProfileService.shared.activeProfileID = sceneProfile
            ProfileService.shared.choices = ["Select": "A"]
            ProfileService.shared.selectionsFail = failure
            defaults.removeObject(forKey: DefaultsKeys.clashMode)
            defaults.removeObject(forKey: "sceneStrictSelections." + sceneProfile.uuidString)
            originalScene.install(profile: sceneProfile, defaults: defaults)
            let baseline = try! ScenarioService.context(defaults: defaults)
            var routing = nextScene; routing.mode = "global"; routing.selections = ["Select": "B"]
            let request = ScenarioService.Review(name: "Routing", context: baseline, target: routing, sourceChanged: false, isUndo: false)
            let applied = await ScenarioService.apply(request, defaults: defaults, storage: historyDir)
            precondition(applied != failure)
            if failure {
                precondition(ProfileService.shared.choices == ["Select": "A"])
                precondition(defaults.object(forKey: DefaultsKeys.clashMode) == nil)
                precondition(trace.events.contains("start:current"))
                precondition(trace.events.firstIndex(of: "selections")! < trace.events.lastIndex(of: "proxy:current")!)
            } else {
                precondition(ProfileService.shared.choices == ["Select": "B"])
                precondition(defaults.string(forKey: DefaultsKeys.clashMode) == "global")
                precondition(trace.events.firstIndex(of: "selections")! < trace.events.firstIndex(of: "proxy:current")!)
                let undone = await ScenarioService.apply(ScenarioService.undoReview(defaults: defaults)!, defaults: defaults, storage: historyDir)
                precondition(undone && ProfileService.shared.choices == ["Select": "A"])
                precondition(defaults.object(forKey: DefaultsKeys.clashMode) == nil)
            }
        }
        ProfileService.shared.selectionsFail = false

        trace.reset(); var validBeforeStop = false
        let cancelledBeforeStop = await ConfigurationCoordinator.replace(previous: old, targetMode: false, restoreProxy: true,
            beforeStop: { if !validBeforeStop { throw CancellationError() } })
        precondition(cancelledBeforeStop == .preparationFailed && !trace.events.contains("stop"))
        trace.reset(); validBeforeStop = true
        let cancelledAfterReadback = await ConfigurationCoordinator.replace(previous: old, targetMode: false, restoreProxy: true,
            verify: { validBeforeStop = false }, beforeStop: { if !validBeforeStop { throw CancellationError() } })
        precondition(cancelledAfterReadback == .restored)
        precondition(trace.events.filter { $0 == "checkpoint" }.count == 1)

        // Migration approval requires a successful live transaction, not an offline save or failed activation.
        for condition in ["live", "stopped", "failure"] {
            resetRecovery(); ProfileService.shared.activeProfileID = sceneProfile
            ProfileService.shared.activeProfileRevision = "new revision"
            originalScene.install(profile: sceneProfile, defaults: defaults)
            let migrating = try! ManualScenario(name: "Migration", profileID: sceneProfile, sourceRevision: "old revision", settings: nextScene)
            try! ScenarioLibrary.save([migrating], directory: sceneDir)
            if condition == "stopped" { ClashViewModel.shared.runtimeState = .stopped }
            if condition == "failure" { trace.buildFails = true }
            let request = try! ScenarioService.review(migrating, defaults: defaults)
            precondition(request.sourceChanged)
            let success = await ScenarioService.apply(request, defaults: defaults, storage: sceneDir)
            precondition(success == (condition != "failure"))
            let saved = try! ScenarioLibrary.load(directory: sceneDir)[0]
            precondition((saved.validatedRevision == "new revision") == (condition == "live"))
            precondition(saved.sourceRevision == "old revision" && saved.id == migrating.id)
            let history = try! SceneExecutionHistory.load(directory: sceneDir)
            precondition(history[0].sceneID == migrating.id)
            precondition(history[0].result.contains(condition == "live" ? "verified" : condition == "stopped" ? "Awaiting" : "Failed"))
            if condition == "live" {
                precondition(!(try! ScenarioService.review(saved, defaults: defaults)).sourceChanged)
                var changed = saved.settings; changed.localRules = "MATCH,REJECT"
                try! ScenarioService.update(saved, name: saved.name, settings: changed,
                    expected: ScenarioService.context(defaults: defaults), defaults: defaults, storage: sceneDir)
                precondition(try! ScenarioLibrary.load(directory: sceneDir)[0].validatedRevision == nil)
            }
        }
        print("PASS: migration approved only after live verification; offline/failure stay blocked; edits invalidate approval; execution history records outcomes")
        print("PASS: stale environment before stop retains runtime; late invalidation restores checkpoint")
        print("PASS: mode/node commit, readback failure rollback, verification before proxy, undo restores missing mode")
        print("PASS: scene editing stays offline, retains identity and rejects stale scenes/settings")
        print("PASS: scene switch/undo, multi-section rollback, stale reviews, profile guard and stopped-core validation")
        print("PASS: egress transaction commit, validation, rollback, stale drafts and stopped core")
        print("PASS: DNS transaction commit, validation, activation/cleanup rollback, stale drafts and stopped core")
        print("PASS: policy parameter transaction commit, validation, activation/cleanup rollback, stale drafts and stopped core")
        print("PASS: stale rule editor cannot overwrite a newer saved draft")
        print("PASS: local rules saved only on success, failure restores missing preference, stopped validation, revision guard")
        print("PASS: explicit recovery missing/mismatched/invalid checkpoints, capture/stop failure, cold start, activation/proxy rollback, failed cleanup")
        print("PASS: production coordinator preparation/activation, proxy failure rollback, stop guards, checkpoint ordering, recovery errors")
    }
}
