import Foundation
import SubscriptionKit

/// Private per-subscription resources and device credentials, shared by configuration and editors.
@MainActor enum ManagedWorkspaceService {
    struct Document: Codable, Equatable, Sendable {
        var resources = ManagedResources.Draft()
        var devices: [DeviceAccess.Device] = []
    }
    struct Snapshot {
        let profile: UUID
        let revision: String
        let original: Data?
        let document: Document
        let source: String
        let policy: String
        let egress: String
        let dns: String
        let rules: String
        var targets: [String] {
            (try? EgressConfiguration.read(PolicyConfiguration.preview(source: ManagedResources.apply(source: source, draft: document.resources), overrides: policy)).targets) ?? ["DIRECT"]
        }
    }
    static var storageDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Ares/managed")
    static var defaults = UserDefaults.standard
    private static func file(_ id: UUID) -> URL { storageDirectory.appendingPathComponent(id.uuidString + ".json") }
    private static func data(_ id: UUID) throws -> Data? {
        let url = file(id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }
    static func remove(_ id: UUID) throws { try write(nil, id: id) }
    static func read(_ id: UUID?) throws -> Document {
        guard let id, let value = try data(id) else { return Document() }
        return try JSONDecoder().decode(Document.self, from: value)
    }
    private static func write(_ value: Data?, id: UUID) throws {
        let url = file(id)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.deletingLastPathComponent().path)
        if let value {
            try value.write(to: url, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } else if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
    static func load() async throws -> Snapshot {
        let profiles = ProfileService.shared
        guard let id = profiles.activeProfileID, let path = profiles.activeProfile?.path else { throw ManagedResources.Failure.invalid("Select or create a subscription first.") }
        let revision = profiles.activeProfileRevision, original = try data(id)
        let document = try original.map { try JSONDecoder().decode(Document.self, from: $0) } ?? Document()
        let defaults = Self.defaults
        let policy = defaults.string(forKey: PolicyGroupService.key(id)) ?? "{}"
        let egress = defaults.string(forKey: EgressSettingsService.key(id)) ?? EgressConfiguration.empty
        let dns = defaults.string(forKey: DNSSettingsService.key(id)) ?? "{}"
        let rules = defaults.string(forKey: DefaultsKeys.localRules) ?? ""
        let source = try await Task.detached { try String(contentsOf: path, encoding: .utf8) }.value
        let result = Snapshot(profile: id, revision: revision, original: original, document: document, source: source, policy: policy, egress: egress, dns: dns, rules: rules)
        guard try current(result) else { throw CancellationError() }
        return result
    }
    private static func current(_ snapshot: Snapshot, storedExpected: Data? = nil) throws -> Bool {
        let defaults = Self.defaults
        let stored = try data(snapshot.profile)
        return snapshot.revision == ProfileService.shared.activeProfileRevision && (storedExpected ?? snapshot.original) == stored &&
            snapshot.policy == (defaults.string(forKey: PolicyGroupService.key(snapshot.profile)) ?? "{}") &&
            snapshot.egress == (defaults.string(forKey: EgressSettingsService.key(snapshot.profile)) ?? EgressConfiguration.empty) &&
            snapshot.dns == (defaults.string(forKey: DNSSettingsService.key(snapshot.profile)) ?? "{}") &&
            snapshot.rules == (defaults.string(forKey: DefaultsKeys.localRules) ?? "")
    }
    static func apply(_ document: Document, snapshot: Snapshot) async throws {
        guard try current(snapshot) else { throw ManagedResources.Failure.invalid("Configuration changed. Reload before applying.") }
        // Structural checks before persistence. Full rules, references and ports are checked by the pinned core.
        let resources = try ManagedResources.apply(source: snapshot.source, draft: document.resources)
        let policies = try PolicyConfiguration.apply(source: resources, overrides: snapshot.policy)
        let egress = try EgressConfiguration.apply(source: policies, overrides: snapshot.egress)
        _ = try DeviceAccess.apply(source: egress, devices: document.devices)
        let app = AppState.shared, vm = ClashViewModel.shared
        guard !vm.isToggling, app.beginOperation("Applying Resources & Devices") else { throw ManagedResources.Failure.invalid("Wait for the current operation to finish.") }
        vm.isToggling = true
        defer { vm.isToggling = false; app.finishOperation() }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(document)
        var storageError = false
        func restore() {
            do { try write(snapshot.original, id: snapshot.profile) } catch { storageError = true }
        }
        if vm.runtimeState.isAPIReady {
            let checkpoint = try await vm.captureRecoveryCheckpoint()
            guard try current(snapshot) else { throw ManagedResources.Failure.invalid("Configuration changed during preparation. Reload before applying.") }
            let outcome = await ConfigurationCoordinator.replace(previous: checkpoint, targetMode: app.tunEnabled, restoreProxy: app.systemProxyEnabled,
                preparePreferences: { do { try write(encoded, id: snapshot.profile) } catch { storageError = true } },
                restorePreferences: restore,
                beforeStop: {
                    guard !storageError, try current(snapshot, storedExpected: encoded) else { throw ManagedResources.Failure.invalid("Private configuration storage failed.") }
                })
            guard outcome == .committed, !storageError else { throw ManagedResources.Failure.invalid(storageError ? "Private storage or recovery failed. Review configuration before retrying." : "Changes were not activated. Previous configuration was retained or recovery was attempted.") }
        } else {
            guard vm.runtimeState == .stopped else { throw ManagedResources.Failure.invalid("Wait for a stable core state.") }
            let mode = app.tunEnabled
            let path = await ConfigService.shared.getConfigPath(tunEnabled: mode)
            let previous: Data? = FileManager.default.fileExists(atPath: path.path) ? try Data(contentsOf: path) : nil
            guard try current(snapshot) else { throw CancellationError() }
            do {
                try write(encoded, id: snapshot.profile)
                try await ConfigService.shared.buildConfig(tunEnabled: mode)
                guard try current(snapshot, storedExpected: encoded) else { throw CancellationError() }
            } catch {
                restore()
                do {
                    if let previous {
                        try previous.write(to: path, options: .atomic)
                        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
                    } else if FileManager.default.fileExists(atPath: path.path) {
                        try FileManager.default.removeItem(at: path)
                    }
                } catch { storageError = true }
                throw ManagedResources.Failure.invalid(storageError ? "Configuration recovery failed." : "Validation failed. Previous settings were retained. Check resource references and ports.")
            }
        }
        NotificationCenter.default.post(name: .sceneManuallyApplied, object: nil)
    }
}
