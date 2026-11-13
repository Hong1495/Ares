import Combine
import Foundation

extension AppState {
    /// Sync status from services (Centralized Heartbeat)
    func syncStatus() {
        // Only sync if we are NOT in the middle of a restart operation
        if !systemIsSleeping && clashViewModel.isRunning && !clashViewModel.isToggling && !isSystemProxyToggling && !isSyncingStatus {
            isSyncingStatus = true
            Task {
                defer { isSyncingStatus = false }
                await syncWithClash()

                // Self-Healing: Verify port consistency
                await verifyAndFixPortMismatches()
            }
        }
    }

    /// Sync state from Clash API
    func syncWithClash() async {
        await Task.yield()
        // 1. Fetch current mode
        if let mode = try? await clashController.getCurrentMode() {
            DispatchQueue.main.async {
                if self.currentMode != mode {
                    self.currentMode = mode
                }
            }
        }

        // 2. Refresh proxies & rules data
        try? await clashController.fetchProxiesData()
        try? await clashController.fetchRules()

        // Counts are available on every page; topology filtering never changes the total.
        await clashController.monitorConnections()
    }

    /// Self-Healing logic to ensure system proxy matches Clash mode
    private func verifyAndFixPortMismatches() async {
        guard systemProxyEnabled else { return }

        // We can't easily check actual system proxy ports without running networksetup
        // which is expensive. Instead, we trust the internal state but force a sync
        // if we detect we just finished a toggle or if things feel "out of sync".

        // For now, let's just make sure the ClashController port is ALWAYS up to date
        let expectedPort = tunEnabled ? ClashPorts.apiTun : ClashPorts.apiNormal
        if clashController.currentPort != expectedPort { clashController.updatePort(tunEnabled: tunEnabled) }
    }

    /// Set Clash mode and sync
    func setMode(_ mode: ClashConfig.Mode) async {
        guard beginOperation("Switching Proxy Mode") else { return }
        defer {
            if operationStatus != nil {
                finishOperation()
            }
        }

        clashViewModel.addLog("[AppState] 🔄 Switching mode to: \(mode.rawValue.uppercased())")

        if !clashViewModel.isRunning {
            NotificationCenter.default.post(name: .sceneManuallyApplied, object: nil)
            currentMode = mode
            UserDefaults.standard.set(mode.rawValue, forKey: DefaultsKeys.clashMode)
            return
        }
        do {
            try await clashController.setMode(mode)
            guard try await clashController.getCurrentMode() == mode else {
                throw NSError(domain: "Mode", code: 1, userInfo: [NSLocalizedDescriptionKey: "Core did not confirm the requested mode"])
            }
            NotificationCenter.default.post(name: .sceneManuallyApplied, object: nil)
            currentMode = mode
            UserDefaults.standard.set(mode.rawValue, forKey: DefaultsKeys.clashMode)
            if (try? await clashViewModel.captureRecoveryCheckpoint()) != nil { await clashViewModel.persistActiveCheckpoint() }
            clashViewModel.addLog("[AppState] ✅ Mode switched to \(mode.rawValue.uppercased())")
        } catch {
            if let actualMode = try? await clashController.getCurrentMode() {
                currentMode = actualMode
            }
            finishOperation(error: "Failed to switch Proxy Mode: \(error.localizedDescription)")
        }
    }
}
