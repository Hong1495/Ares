import Combine
import Foundation

extension AppState {
    // MARK: - MITM Toggle

    /// Toggle MITM mode
    func toggleMITM() {
        // Guard against rapid toggling
        guard !isMITMToggling else {
            clashViewModel.addLog("[AppState] ⚠️ MITM toggle in progress, ignoring")
            return
        }
        isMITMToggling = true

        print("[AppState] switch MITM mode")

        let isRunning = NetworkMITMService.shared.isRunning
        let newState = !isRunning

        Task { @MainActor in
            defer { self.isMITMToggling = false }
            if newState {
                // STEP 1: Start MITM first to get the port number
                await NetworkMITMService.shared.start()

                // STEP 2: If TUN mode is active, restart Clash with MITM routing rules
                // Now MITM is running, so ConfigService.buildConfig() will inject MITM rules
                if self.tunEnabled && self.clashViewModel.isRunning {
                    let mitmPort = NetworkMITMService.shared.currentPort
                    self.clashViewModel.addLog("[MITM] 🔄 TUN mode active - restarting Clash with MITM routing to port \(mitmPort)...")

                    await self.clashViewModel.stopCore(intendedRestart: true)
                    await self.clashViewModel.startCore(isRestart: true)

                    let isReady = await ClashController.shared.waitForAPIReady(timeout: 5.0)
                    if isReady {
                        self.clashViewModel.addLog("[MITM] ✅ Clash restarted with MITM routing rules")
                    } else {
                        self.clashViewModel.addLog("[MITM] ⚠️ Clash restart timeout")
                    }
                }
            } else {
                await NetworkMITMService.shared.stop()

                // If TUN mode is active and TURNING OFF MITM, restart Clash to remove MITM config
                if self.tunEnabled && self.clashViewModel.isRunning {
                    self.clashViewModel.addLog("[MITM] 🔄 TUN mode active - rebuilding Clash config after MITM disabled...")

                    await self.clashViewModel.stopCore(intendedRestart: true)
                    await self.clashViewModel.startCore(isRestart: true)

                    let isReady = await ClashController.shared.waitForAPIReady(timeout: 5.0)
                    if isReady {
                        self.clashViewModel.addLog("[MITM] ✅ Clash restarted without MITM routing")
                    }
                }
            }

            // Trigger UI update
            self.objectWillChange.send()

            // Refresh system proxy if it is enabled to apply new port rules
            // In TUN mode: system proxy points to Clash, traffic flows TUN->Clash->MITM
            // In non-TUN mode: system proxy points to MITM, traffic flows SystemProxy->MITM->Clash
            if self.systemProxyEnabled {
                await self.enableSystemProxy()
            }
        }
    }
}
