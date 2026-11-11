import Combine
import Foundation

extension AppState {
    func toggleMITM() {
        guard !isMITMToggling, !clashViewModel.isToggling, beginOperation("Updating MITM Shield") else { return }
        isMITMToggling = true
        clashViewModel.isToggling = true
        Task { @MainActor in
            defer { isMITMToggling = false; clashViewModel.isToggling = false; objectWillChange.send() }
            let mitm = NetworkMITMService.shared
            let enabling = !mitm.isRunning
            let wasRunning = clashViewModel.isRunning
            let oldRouting = mitm.routingEnabled
            if enabling {
                guard wasRunning else { finishOperation(error: "Start the core before enabling MITM."); return }
                guard await mitm.start() else { finishOperation(error: "MITM listener failed to start."); return }
            }
            mitm.routingEnabled = enabling
            let migrated = await ListenerMigration.retire(
                migrateRoutes: {
                    if self.tunEnabled && wasRunning { return await self.restartForMITMRouting() }
                    // A failed runtime might still contain routes to this listener.
                    if self.tunEnabled && !enabling && self.clashViewModel.runtimeState != .stopped { return false }
                    return true
                },
                migrateProxy: {
                    if self.systemProxyEnabled { return await self.enableSystemProxy() }
                    return true
                },
                stopListener: { if !enabling { await mitm.stop() } })
            if migrated { finishOperation(); return }
            mitm.routingEnabled = oldRouting
            var recovered = true
            if tunEnabled && wasRunning { recovered = await restartForMITMRouting() }
            if recovered && systemProxyEnabled { recovered = await enableSystemProxy() }
            // Keep the listener alive when recovery is uncertain: traffic may still target it.
            if recovered && enabling { await mitm.stop() }
            finishOperation(error: recovered ? "MITM change failed; previous routing was restored." : "MITM routing recovery could not be verified. The listener was kept running.")
        }
    }

    private func restartForMITMRouting() async -> Bool {
        do { try await ConfigService.shared.buildConfig(tunEnabled: tunEnabled) }
        catch { return false }
        guard await clashViewModel.stopCore(intendedRestart: true) else { return false }
        await clashViewModel.startCore(isRestart: true)
        return clashViewModel.runtimeState.isAPIReady
    }
}
