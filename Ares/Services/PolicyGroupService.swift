import Foundation
import SubscriptionKit

@MainActor enum PolicyGroupService {
    struct Snapshot {
        let revision: String
        let storageKey: String
        let stored: String
        let inherited: [PolicyConfiguration.Group]
        let effective: [PolicyConfiguration.Group]
        var source = "{}"
        var localRules = ""
    }
    static var canReadRuntime: Bool {
        let vm = ClashViewModel.shared
        return vm.runtimeState.isAPIReady && !vm.isToggling && vm.appliedProfileRevision == ProfileService.shared.activeProfileRevision
    }
    static func key(_ id: UUID) -> String { "policyGroupOverrides." + id.uuidString }
    static func load() async throws -> Snapshot {
        let profiles = ProfileService.shared
        guard let id = profiles.activeProfileID, let path = profiles.activeProfile?.path else { throw URLError(.fileDoesNotExist) }
        let revision = profiles.activeProfileRevision
        let key = key(id)
        let stored = UserDefaults.standard.string(forKey: key) ?? "{}"
        let localRules = UserDefaults.standard.string(forKey: DefaultsKeys.localRules) ?? ""
        let groups = try await ConfigService.shared.policyGroups(profilePath: path, overrides: stored)
        guard revision == profiles.activeProfileRevision, stored == (UserDefaults.standard.string(forKey: key) ?? "{}"), localRules == (UserDefaults.standard.string(forKey: DefaultsKeys.localRules) ?? "") else { throw CancellationError() }
        return Snapshot(revision: revision, storageKey: key, stored: stored, inherited: groups.0, effective: groups.1, source: groups.2, localRules: localRules)
    }
    static func apply(_ overrides: String, snapshot: Snapshot, localRules: String? = nil, defaults: UserDefaults = .standard) async -> Bool {
        let app = AppState.shared, vm = ClashViewModel.shared
        guard snapshot.revision == ProfileService.shared.activeProfileRevision,
              snapshot.stored == (defaults.string(forKey: snapshot.storageKey) ?? "{}") else {
            app.reportError("This subscription or its policy overrides changed. Reopen the editor before applying.")
            return false
        }
        if localRules != nil, snapshot.localRules != (defaults.string(forKey: DefaultsKeys.localRules) ?? "") {
            app.reportError("Local rules changed. Reopen the policy editor."); return false
        }
        let expected: [PolicyConfiguration.Group]
        do { expected = try PolicyConfiguration.read(PolicyConfiguration.apply(source: snapshot.source, overrides: overrides)) }
        catch { app.reportError(error.localizedDescription); return false }
        guard app.beginOperation("Applying Policy Group") else { return false }
        vm.isToggling = true
        defer { vm.isToggling = false; app.finishOperation(error: app.lastOperationError) }
        let profile = ProfileService.shared.activeProfileID
        let previousChoices = ProfileService.shared.savedSelections()
        let removedNames = Set(snapshot.effective.map(\.name)).subtracting(expected.map(\.name))
        let targetChoices = previousChoices.filter { name, choice in
            if name == "GLOBAL" { return !removedNames.contains(choice) }
            guard let group = expected.first(where: { $0.name == name }), group.type != "load-balance" else { return false }
            let dynamic = !group.providers.isEmpty || ["include-all", "include-all-proxies", "include-all-providers"].contains { group.fields[$0] == "true" }
            return !removedNames.contains(choice) && (dynamic || group.members.contains(choice))
        }
        let previousRules = defaults.object(forKey: DefaultsKeys.localRules)
        let previous = defaults.object(forKey: snapshot.storageKey)
        func install() {
            if let profile { ProfileService.shared.replaceSavedSelections(targetChoices, profile: profile, defaults: defaults) }
            defaults.set(overrides, forKey: snapshot.storageKey)
            if let localRules { defaults.set(localRules, forKey: DefaultsKeys.localRules) }
        }
        func restore() {
            if let profile { ProfileService.shared.replaceSavedSelections(previousChoices, profile: profile, defaults: defaults) }
            if localRules != nil {
                if let previousRules { defaults.set(previousRules, forKey: DefaultsKeys.localRules) }
                else { defaults.removeObject(forKey: DefaultsKeys.localRules) }
            }
            if let previous { defaults.set(previous, forKey: snapshot.storageKey) }
            else { defaults.removeObject(forKey: snapshot.storageKey) }
        }
        if vm.runtimeState.isAPIReady {
            do {
                let checkpoint = try await vm.captureRecoveryCheckpoint()
                guard snapshot.revision == ProfileService.shared.activeProfileRevision,
                      snapshot.stored == (defaults.string(forKey: snapshot.storageKey) ?? "{}"),
                      localRules == nil || snapshot.localRules == (defaults.string(forKey: DefaultsKeys.localRules) ?? "") else { throw CancellationError() }
                let outcome = await ConfigurationCoordinator.replace(previous: checkpoint, targetMode: app.tunEnabled,
                    restoreProxy: app.systemProxyEnabled,
                    preparePreferences: { install() }, restorePreferences: { restore() }, verify: {
                        try await ClashController.shared.fetchProxiesData()
                        let live = ClashController.shared.proxyGroups
                        let types = ["select": "Selector", "url-test": "URLTest", "fallback": "Fallback", "load-balance": "LoadBalance"]
                        for group in expected {
                            guard let actual = live.first(where: { $0.name == group.name && $0.type == types[group.type] }) else { throw URLError(.cannotParseResponse) }
                            // Explicit member order is observable. Filters may legitimately remove members;
                            // dynamic resources are validated by the core rather than guessed by the UI.
                            if ["filter", "exclude-filter", "exclude-type"].allSatisfy({ group.fields[$0, default: ""].isEmpty }) {
                                var position = actual.all.startIndex
                                for member in group.members {
                                    guard let index = actual.all[position...].firstIndex(of: member) else { throw URLError(.cannotParseResponse) }
                                    position = actual.all.index(after: index)
                                }
                            }
                        }
                        let removed = Set(snapshot.effective.map(\.name)).subtracting(expected.map(\.name))
                        guard !live.contains(where: { removed.contains($0.name) }) else { throw URLError(.cannotParseResponse) }
                    })
                guard outcome == .committed else {
                    restore(); app.reportError("Policy changes were not applied (\(outcome)). Review the configuration and runtime status.")
                    return false
                }
            } catch { app.reportError("The running configuration could not be captured. No policy settings were changed."); return false }
        } else {
            guard vm.runtimeState == .stopped else { app.reportError("Wait for a stable core state before applying policy changes."); return false }
            install()
            do { try await ConfigService.shared.buildConfig(tunEnabled: app.tunEnabled) }
            catch { restore(); app.reportError("Policy validation failed. Previous settings were retained."); return false }
        }
        return true
    }
}
