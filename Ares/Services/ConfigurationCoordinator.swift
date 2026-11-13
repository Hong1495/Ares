import Foundation

/// Shared replacement boundary. Callers hold AppState's operation gate and own preference rollback.
@MainActor enum ConfigurationCoordinator {
    static func activate(configuration: String? = nil, recovery: RuntimeCheckpoint? = nil,
                         restoreProxy: Bool) async -> Bool {
        let vm = ClashViewModel.shared
        await vm.startCore(isRestart: true, preparedConfiguration: configuration, recovery: recovery, persistCheckpoint: false)
        guard vm.runtimeState.isAPIReady else { return false }
        if NetworkMITMService.shared.isRunning {
            guard await NetworkMITMService.shared.updateUpstream(tunEnabled: AppState.shared.tunEnabled) else { return false }
        }
        if restoreProxy {
            guard await AppState.shared.enableSystemProxy(expectedRevision: recovery?.profileRevision) else { return false }
        }
        await vm.persistActiveCheckpoint()
        return true
    }

    static func replace(
        previous: RuntimeCheckpoint,
        targetMode: Bool,
        restoreProxy: Bool,
        preparePreferences: () -> Void = {},
        activatePreferences: () -> Void = {},
        restorePreferences: () -> Void = {}
    ) async -> ConfigurationTransition.Outcome {
        let vm = ClashViewModel.shared
        let revision = ProfileService.shared.activeProfileRevision
        var prepared: String?
        return await ConfigurationTransition.perform(
            prepare: {
                preparePreferences()
                try await ConfigService.shared.buildConfig(tunEnabled: targetMode)
                prepared = try await ConfigService.shared.savedConfiguration(tunEnabled: targetMode)
                guard revision == ProfileService.shared.activeProfileRevision else { throw CancellationError() }
            },
            stop: { await vm.stopCore(intendedRestart: true) },
            activate: {
                guard revision == ProfileService.shared.activeProfileRevision, let prepared else { return false }
                activatePreferences()
                return await activate(configuration: prepared, restoreProxy: restoreProxy)
            },
            stopFailed: { await vm.stopCore(intendedRestart: true) },
            restore: {
                restorePreferences()
                return await Task { @MainActor in
                    await activate(recovery: previous, restoreProxy: restoreProxy)
                }.value
            },
            undoPreparation: {
                restorePreferences()
                return await Task { @MainActor in
                    do {
                        try await ConfigService.shared.restoreConfiguration(previous.configuration, tunEnabled: previous.tunEnabled)
                        return true
                    } catch { return false }
                }.value
            })
    }
}

extension ConfigurationCoordinator {
    /// Explicit recovery action, never silently substitutes a different subscription on launch.
    static func restoreLastSuccessful() async -> Bool {
        let app = AppState.shared
        let vm = ClashViewModel.shared
        guard !vm.isToggling, app.beginOperation("Restoring Verified Configuration") else { return false }
        vm.isToggling = true
        defer { vm.isToggling = false; app.finishOperation(error: app.lastOperationError) }
        let checkpoint: RuntimeCheckpoint
        do { checkpoint = try await ConfigService.shared.successfulRuntime(tunEnabled: app.tunEnabled) }
        catch { app.reportError("No saved verified configuration exists for this mode."); return false }
        guard checkpoint.profileID == ProfileService.shared.activeProfileID else {
            app.reportError("Select the subscription associated with the saved recovery configuration first.")
            return false
        }
        // Capture before replacing the file, and never interrupt an unverifiable active core.
        let previous: RuntimeCheckpoint?
        if vm.runtimeState.isAPIReady {
            do { previous = try await vm.captureRecoveryCheckpoint() }
            catch { app.reportError("The current runtime could not be captured. Recovery was cancelled."); return false }
        } else { previous = nil }
        do { try await ConfigService.shared.restoreConfiguration(checkpoint.configuration, tunEnabled: app.tunEnabled) }
        catch { app.reportError("The recovery configuration could not be validated. The running core was kept."); return false }
        let proxy = app.systemProxyEnabled
        guard await vm.stopCore(intendedRestart: true) else {
            if let previous {
                do { try await ConfigService.shared.restoreConfiguration(previous.configuration, tunEnabled: previous.tunEnabled) }
                catch { app.reportError("Core shutdown and saved configuration recovery failed."); return false }
            }
            app.reportError("Core shutdown could not be verified. Recovery was cancelled.")
            return false
        }
        if await activate(recovery: checkpoint, restoreProxy: proxy) { return true }
        guard await vm.stopCore(intendedRestart: true) else {
            app.reportError("Recovery failed and the new process could not be stopped.")
            return false
        }
        if let previous, await activate(recovery: previous, restoreProxy: proxy) {
            app.reportError("The saved recovery configuration failed. The previous runtime was restored.")
        } else { app.reportError("The saved recovery configuration could not start. The core remains unavailable.") }
        return false
    }
}
