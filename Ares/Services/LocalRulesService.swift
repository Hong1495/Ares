import Foundation

/// Draft editing never changes defaults; apply uses the shared validated replacement boundary.
@MainActor enum LocalRulesService {
    static func apply(_ draft: String, expectedRevision: String, expectedRules: String? = nil, defaults: UserDefaults = .standard) async -> Bool {
        if let expectedRules, (defaults.string(forKey: DefaultsKeys.localRules) ?? "") != expectedRules {
            AppState.shared.reportError("Local rules changed while this editor was open. Reopen it before applying.")
            return false
        }
        let app = AppState.shared
        let vm = ClashViewModel.shared
        guard expectedRevision == ProfileService.shared.activeProfileRevision else {
            app.reportError("The subscription changed. Reopen the rule editor before applying.")
            return false
        }
        guard app.beginOperation("Applying Local Rules") else { return false }
        vm.isToggling = true
        defer { vm.isToggling = false; app.finishOperation(error: app.lastOperationError) }
        let previous = defaults.object(forKey: DefaultsKeys.localRules)
        func restorePreference() {
            if let previous { defaults.set(previous, forKey: DefaultsKeys.localRules) }
            else { defaults.removeObject(forKey: DefaultsKeys.localRules) }
        }
        if vm.runtimeState.isAPIReady {
            do {
                let checkpoint = try await vm.captureRecoveryCheckpoint()
                let outcome = await ConfigurationCoordinator.replace(previous: checkpoint,
                    targetMode: app.tunEnabled, restoreProxy: app.systemProxyEnabled,
                    preparePreferences: { defaults.set(draft, forKey: DefaultsKeys.localRules) },
                    restorePreferences: { restorePreference() })
                guard outcome == .committed else {
                    restorePreference()
                    app.reportError("Local rules were not applied (\(outcome)). Review the rules and runtime status.")
                    return false
                }
            } catch {
                app.reportError("The current runtime could not be captured. Local rules were not changed.")
                return false
            }
        } else {
            guard vm.runtimeState == .stopped else { app.reportError("Wait for the core to become ready before applying rules."); return false }
            defaults.set(draft, forKey: DefaultsKeys.localRules)
            do { try await ConfigService.shared.buildConfig(tunEnabled: app.tunEnabled) }
            catch {
                restorePreference()
                app.reportError("Local rule validation failed. The previous configuration was retained.")
                return false
            }
        }
        return true
    }
}
