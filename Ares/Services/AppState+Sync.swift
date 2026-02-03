import Combine
import Foundation

extension AppState {
    /// Sync status from services (Centralized Heartbeat)
    func syncStatus() {
        // Only sync if we are NOT in the middle of a restart operation
        if clashViewModel.isRunning && !clashViewModel.isToggling && !isSystemProxyToggling {
            Task {
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

        // 3. Monitor connections count (only when topology/routing views are active)
        let shouldUpdateTopology = selection == .topology || selection == .routeMap
        if shouldUpdateTopology {
            await clashController.monitorConnections()
        }
    }

    /// Self-Healing logic to ensure system proxy matches Clash mode
    private func verifyAndFixPortMismatches() async {
        guard systemProxyEnabled else { return }

        // We can't easily check actual system proxy ports without running networksetup
        // which is expensive. Instead, we trust the internal state but force a sync
        // if we detect we just finished a toggle or if things feel "out of sync".

        // For now, let's just make sure the ClashController port is ALWAYS up to date
        clashController.updatePort(tunEnabled: tunEnabled)
    }

    /// Set Clash mode and sync
    func setMode(_ mode: ClashConfig.Mode) async {
        clashViewModel.addLog("[AppState] 🔄 Switching mode to: \(mode.rawValue.uppercased())")

        // Update UI immediately (optimistic update)
        objectWillChange.send()
        currentMode = mode

        // Then sync with Clash API
        do {
            try await clashController.setMode(mode)
            clashViewModel.addLog("[AppState] ✅ Mode switched to \(mode.rawValue.uppercased())")
        } catch {
            clashViewModel.addLog("[AppState] ❌ Failed to set mode: \(error)")
        }
    }
}
