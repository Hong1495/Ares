import Foundation
import SubscriptionKit

@MainActor enum EgressSettingsService {
    struct Snapshot {
        let revision: String
        let storageKey: String
        let stored: String
        let inherited: EgressConfiguration.Document
        let effective: EgressConfiguration.Document
        var policyOverrides = "{}"
        var policyKey: String? = nil
    }
    static func key(_ id: UUID) -> String { "egressOverrides." + id.uuidString }
    static func load() async throws -> Snapshot {
        let profiles = ProfileService.shared
        guard let id = profiles.activeProfileID, let path = profiles.activeProfile?.path else { throw URLError(.fileDoesNotExist) }
        let revision = profiles.activeProfileRevision, key = key(id)
        let stored = UserDefaults.standard.string(forKey: key) ?? EgressConfiguration.empty
        let policyKey = "policyGroupOverrides." + id.uuidString
        let policy = UserDefaults.standard.string(forKey: policyKey) ?? "{}"
        let documents = try await ConfigService.shared.egressSettings(profilePath: path, overrides: stored, policyOverrides: policy)
        guard revision == profiles.activeProfileRevision, stored == (UserDefaults.standard.string(forKey: key) ?? EgressConfiguration.empty), policy == (UserDefaults.standard.string(forKey: policyKey) ?? "{}") else { throw CancellationError() }
        return Snapshot(revision: revision, storageKey: key, stored: stored, inherited: documents.0, effective: documents.1, policyOverrides: policy, policyKey: policyKey)
    }
    static func apply(_ overrides: String, snapshot: Snapshot, defaults: UserDefaults = .standard) async -> Bool {
        let app = AppState.shared, vm = ClashViewModel.shared
        guard snapshot.revision == ProfileService.shared.activeProfileRevision,
              snapshot.stored == (defaults.string(forKey: snapshot.storageKey) ?? EgressConfiguration.empty) else {
            app.reportError("The subscription or its routing overrides changed. Reopen the editor before applying."); return false
        }
        if let key = snapshot.policyKey, snapshot.policyOverrides != (defaults.string(forKey: key) ?? "{}") {
            app.reportError("Policy groups changed. Reopen Routing & Listeners before applying."); return false
        }
        guard app.beginOperation("Applying Routing & Listeners") else { return false }
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
                    restore(); app.reportError("Routing changes were not applied (\(outcome)). Check references, interfaces and listener ports."); return false
                }
            } catch { app.reportError("The running configuration could not be captured. No routing settings were changed."); return false }
        } else {
            guard vm.runtimeState == .stopped else { app.reportError("Wait for a stable core state before applying routing changes."); return false }
            defaults.set(overrides, forKey: snapshot.storageKey)
            do { try await ConfigService.shared.buildConfig(tunEnabled: app.tunEnabled) }
            catch { restore(); app.reportError("Routing validation failed. Previous settings were retained."); return false }
        }
        return true
    }
}
