import Foundation
import SubscriptionKit

@MainActor enum DNSSettingsService {
    struct Snapshot {
        let revision: String
        let storageKey: String
        let stored: String
        let inherited: [String: String]
        let effective: [String: String]
        let sources: [String: String]
    }
    static var canReadRuntime: Bool {
        let vm = ClashViewModel.shared
        return vm.runtimeState.isAPIReady && !vm.isToggling && vm.appliedProfileRevision == ProfileService.shared.activeProfileRevision
    }
    static func key(_ id: UUID) -> String { "dnsOverrides." + id.uuidString }
    static func load() async throws -> Snapshot {
        let profiles = ProfileService.shared
        guard let id = profiles.activeProfileID, let path = profiles.activeProfile?.path else { throw URLError(.fileDoesNotExist) }
        let revision = profiles.activeProfileRevision
        let key = key(id)
        let stored = UserDefaults.standard.string(forKey: key) ?? "{}"
        let groups = try await ConfigService.shared.dnsSettings(profilePath: path, overrides: stored)
        guard revision == profiles.activeProfileRevision, stored == (UserDefaults.standard.string(forKey: key) ?? "{}") else { throw CancellationError() }
        return Snapshot(revision: revision, storageKey: key, stored: stored, inherited: groups.0, effective: groups.1, sources: groups.2)
    }
    static func apply(_ overrides: String, snapshot: Snapshot, defaults: UserDefaults = .standard) async -> Bool {
        let app = AppState.shared, vm = ClashViewModel.shared
        guard snapshot.revision == ProfileService.shared.activeProfileRevision,
              snapshot.stored == (defaults.string(forKey: snapshot.storageKey) ?? "{}") else {
            app.reportError("This subscription or its DNS overrides changed. Reopen the editor before applying.")
            return false
        }
        do { _ = try DNSConfiguration.apply(source: "{}", overrides: overrides) }
        catch { app.reportError("DNS overrides contain an invalid field or YAML value."); return false }
        guard app.beginOperation("Applying DNS Settings") else { return false }
        vm.isToggling = true
        defer { vm.isToggling = false; app.finishOperation(error: app.lastOperationError) }
        let previous = defaults.object(forKey: snapshot.storageKey)
        func restore() {
            if let previous { defaults.set(previous, forKey: snapshot.storageKey) }
            else { defaults.removeObject(forKey: snapshot.storageKey) }
        }
        if vm.runtimeState.isAPIReady {
            do {
                let checkpoint = try await vm.captureRecoveryCheckpoint()
                let outcome = await ConfigurationCoordinator.replace(previous: checkpoint, targetMode: app.tunEnabled,
                    restoreProxy: app.systemProxyEnabled,
                    preparePreferences: { defaults.set(overrides, forKey: snapshot.storageKey) }, restorePreferences: { restore() })
                guard outcome == .committed else {
                    restore(); app.reportError("DNS changes were not applied (\(outcome)). Review the configuration and runtime status.")
                    return false
                }
            } catch { app.reportError("The running configuration could not be captured. No DNS settings were changed."); return false }
        } else {
            guard vm.runtimeState == .stopped else { app.reportError("Wait for a stable core state before applying DNS changes."); return false }
            defaults.set(overrides, forKey: snapshot.storageKey)
            do { try await ConfigService.shared.buildConfig(tunEnabled: app.tunEnabled) }
            catch { restore(); app.reportError("DNS validation failed. Previous settings were retained."); return false }
        }
        return true
    }
}
