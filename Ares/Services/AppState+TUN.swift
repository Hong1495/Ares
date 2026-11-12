import Combine
import Foundation

extension AppState {
    func toggleTUN() {
        guard !isTUNToggling, !clashViewModel.isToggling, beginOperation("Switching TUN Mode") else { return }
        isTUNToggling = true
        clashViewModel.isToggling = true
        let oldTUN = tunEnabled
        let wasRunning = clashViewModel.isRunning
        let hadProxy = systemProxyEnabled
        Task { @MainActor in
            defer { isTUNToggling = false; clashViewModel.isToggling = false }
            // Enabling TUN is a connection action, even if no core is running.
            if !wasRunning {
                guard !oldTUN else {
                    setTUNConfiguration(false)
                    finishOperation()
                    return
                }
                let outcome = await RuntimeTransition.startStopped(
                    activate: {
                        self.setTUNConfiguration(true)
                        return await self.startAndVerifyTUN(expected: true, restoreProxy: hadProxy)
                    },
                    stopFailed: { await self.clashViewModel.stopCore(intendedRestart: true) },
                    restoreSettings: { self.setTUNConfiguration(oldTUN) })
                switch outcome {
                case .committed: finishOperation()
                case .restored: finishOperation(error: "TUN could not start. The previous setting was restored.")
                default: finishOperation(error: "TUN startup failed and core cleanup could not be verified.")
                }
                return
            }
            if !oldTUN, !(await PrivilegeService.shared.checkPrivileges()) {
                guard await PrivilegeService.shared.installSudoers(), await PrivilegeService.shared.checkPrivileges() else {
                    finishOperation(error: "TUN permission unavailable; the running core was kept.")
                    return
                }
            }
            // Compile/validate the target configuration before interrupting the old core.
            do { try await ConfigService.shared.buildConfig(tunEnabled: !oldTUN) }
            catch { finishOperation(error: error.localizedDescription); return }
            let outcome = await RuntimeTransition.perform(
                stopCurrent: { await self.clashViewModel.stopCore(intendedRestart: true) },
                activateNew: {
                    self.setTUNConfiguration(!oldTUN)
                    return await self.startAndVerifyTUN(expected: !oldTUN, restoreProxy: hadProxy)
                },
                stopNew: { await self.clashViewModel.stopCore(intendedRestart: true) },
                restorePrevious: {
                    self.setTUNConfiguration(oldTUN)
                    return await self.startAndVerifyTUN(expected: oldTUN, restoreProxy: hadProxy)
                })
            switch outcome {
            case .committed: finishOperation()
            case .unchanged: finishOperation(error: "Core could not stop; TUN switch cancelled.")
            case .restored: finishOperation(error: "TUN switch failed; the previous core and proxy configuration were restored.")
            case .recoveryRequired: finishOperation(error: "TUN switch failed; recovery of the previous core or proxy could not be verified.")
            }
        }
    }

    private func setTUNConfiguration(_ enabled: Bool) {
        tunEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: DefaultsKeys.tunEnabled)
        clashController.updatePort(tunEnabled: enabled)
    }

    private func startAndVerifyTUN(expected: Bool, restoreProxy: Bool) async -> Bool {
        await clashViewModel.startCore(isRestart: true)
        guard clashViewModel.runtimeState.isAPIReady else { return false }
        do {
            guard let url = URL(string: "\(clashController.baseURL)/configs") else { return false }
            let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 5))
            try CoreAPIContract.requireSuccess(response)
            try CoreAPIContract.verifyTUN(data, expected: expected)
            if NetworkMITMService.shared.isRunning {
                guard await NetworkMITMService.shared.updateUpstream(tunEnabled: expected) else { return false }
            }
            if restoreProxy { return await enableSystemProxy() }
            return true
        } catch { return false }
    }
}
