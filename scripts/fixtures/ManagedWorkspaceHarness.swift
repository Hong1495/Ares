import Foundation
import SubscriptionKit

@MainActor final class ProfileService {
    static let shared = ProfileService()
    struct Profile { let path: URL? }
    var activeProfileID: UUID? = UUID()
    var activeProfile: Profile?
    var activeProfileRevision = "r1"
}
@MainActor enum PolicyGroupService { static func key(_ id: UUID) -> String { "policy." + id.uuidString } }
@MainActor enum EgressSettingsService { static func key(_ id: UUID) -> String { "egress." + id.uuidString } }
@MainActor enum DNSSettingsService { static func key(_ id: UUID) -> String { "dns." + id.uuidString } }
enum DefaultsKeys { static let localRules = "rules" }
extension Notification.Name { static let sceneManuallyApplied = Notification.Name("isolated.managed") }
struct RuntimeCheckpoint {}
@MainActor final class AppState {
    static let shared = AppState()
    var tunEnabled = false, systemProxyEnabled = false, busy = false
    func beginOperation(_ name: String) -> Bool { if busy { return false }; busy = true; return true }
    func finishOperation() { busy = false }
}
@MainActor final class ClashViewModel {
    static let shared = ClashViewModel()
    enum State { case running, stopped; var isAPIReady: Bool { self == .running } }
    var runtimeState = State.stopped, isToggling = false
    var onCapture: (() -> Void)?
    func captureRecoveryCheckpoint() async throws -> RuntimeCheckpoint { onCapture?(); return RuntimeCheckpoint() }
}
@MainActor final class ConfigService {
    static let shared = ConfigService()
    var fails = false
    var onBuilt: (() -> Void)?
    var path = URL(fileURLWithPath: "/unused")
    func getConfigPath(tunEnabled: Bool) -> URL { path }
    func buildConfig(tunEnabled: Bool) async throws {
        if fails { throw URLError(.cannotParseResponse) }
        let doc = try ManagedWorkspaceService.read(ProfileService.shared.activeProfileID)
        precondition(!doc.resources.nodes.isEmpty)
        try Data("generated".utf8).write(to: path)
        onBuilt?()
    }
}
@MainActor enum ConfigurationCoordinator {
    enum Outcome { case committed, restored }
    static var failActivation = false
    static var onPrepared: (() -> Void)?
    static func replace(previous: RuntimeCheckpoint, targetMode: Bool, restoreProxy: Bool,
                        preparePreferences: () -> Void, restorePreferences: () -> Void,
                        beforeStop: () throws -> Void) async -> Outcome {
        preparePreferences(); onPrepared?()
        do { try beforeStop(); try await ConfigService.shared.buildConfig(tunEnabled: targetMode) }
        catch { restorePreferences(); return .restored }
        if failActivation { restorePreferences(); return .restored }
        return .committed
    }
}
func expect(_ result: Bool) { precondition(result) }
@main struct Harness {
    @MainActor static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ares-managed-harness-" + UUID().uuidString)
        let suite = "ares-managed-harness-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { try? FileManager.default.removeItem(at: directory); defaults.removePersistentDomain(forName: suite) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        ManagedWorkspaceService.storageDirectory = directory.appendingPathComponent("private")
        ManagedWorkspaceService.defaults = defaults
        ConfigService.shared.path = directory.appendingPathComponent("generated.yaml")
        let source = directory.appendingPathComponent("source.yaml")
        try "proxies: []\nproxy-groups: []".write(to: source, atomically: true, encoding: .utf8)
        ProfileService.shared.activeProfile = .init(path: source)
        let original = try await ManagedWorkspaceService.load()
        var draft = original.document
        draft.resources.nodes["Local"] = "type: http\nserver: 127.0.0.1\nport: 8080"
        ConfigService.shared.fails = true
        do { try await ManagedWorkspaceService.apply(draft, snapshot: original); preconditionFailure("validation failure accepted") } catch {}
        try expect(ManagedWorkspaceService.read(original.profile) == original.document)
        ConfigService.shared.fails = false
        try await ManagedWorkspaceService.apply(draft, snapshot: original)
        try expect(ManagedWorkspaceService.read(original.profile) == draft)
        let file = ManagedWorkspaceService.storageDirectory.appendingPathComponent(original.profile.uuidString + ".json")
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        precondition((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        do { try await ManagedWorkspaceService.apply(original.document, snapshot: original); preconditionFailure("stale editor accepted") } catch {}
        let fresh = try await ManagedWorkspaceService.load()
        var edited = fresh.document; edited.resources.nodes["Second"] = "type: http\nserver: 127.0.0.1\nport: 8081"
        let saved = try Data(contentsOf: ConfigService.shared.path)
        ConfigService.shared.onBuilt = { defaults.set("concurrent", forKey: "rules") }
        do { try await ManagedWorkspaceService.apply(edited, snapshot: fresh); preconditionFailure("stale stopped build accepted") } catch {}
        try expect(Data(contentsOf: ConfigService.shared.path) == saved)
        try expect(ManagedWorkspaceService.read(original.profile) == draft)
        ConfigService.shared.onBuilt = nil; defaults.removeObject(forKey: "rules")
        ClashViewModel.shared.runtimeState = .running
        ConfigurationCoordinator.failActivation = true
        do { try await ManagedWorkspaceService.apply(edited, snapshot: fresh); preconditionFailure("activation failure accepted") } catch {}
        try expect(ManagedWorkspaceService.read(original.profile) == draft)
        ConfigurationCoordinator.failActivation = false
        ClashViewModel.shared.onCapture = { ProfileService.shared.activeProfileRevision = "r2" }
        do { try await ManagedWorkspaceService.apply(edited, snapshot: fresh); preconditionFailure("stale checkpoint accepted") } catch {}
        try expect(ManagedWorkspaceService.read(original.profile) == draft)
        ClashViewModel.shared.onCapture = nil; ProfileService.shared.activeProfileRevision = "r1"
        ConfigurationCoordinator.onPrepared = { defaults.set("changed", forKey: "rules") }
        do { try await ManagedWorkspaceService.apply(edited, snapshot: fresh); preconditionFailure("concurrent rule edit accepted") } catch {}
        try expect(ManagedWorkspaceService.read(original.profile) == draft)
        ConfigurationCoordinator.onPrepared = nil; defaults.removeObject(forKey: "rules")
        try await ManagedWorkspaceService.apply(edited, snapshot: fresh)
        try expect(ManagedWorkspaceService.read(original.profile) == edited)
        try Data("corrupt".utf8).write(to: file)
        do { _ = try await ManagedWorkspaceService.load(); preconditionFailure("corrupt private store replaced") } catch {}
        try expect(Data(contentsOf: file) == Data("corrupt".utf8))
        print("PASS: managed production service storage permissions, stopped validation, running rollback, stale drafts/checkpoints, concurrent rules, corrupt store preservation")
    }
}
