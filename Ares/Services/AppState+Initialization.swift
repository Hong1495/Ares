import Foundation

extension AppState {
    /// Async initialization sequence
    func initialize() async {
        clashViewModel.addLog("[AppState] 🚀 Initializing application state...")

        // 1. Sync preferences and system state (No network calls yet)
        systemProxyEnabled = UserDefaults.standard.bool(forKey: DefaultsKeys.systemProxyEnabled)
        // Check actual system state only if preference is missing? No, user preference dictates action.
        // If user wants it ON, we will enforce it later in AresApp.

        // 2. Auto-detect and repair stale sudoers paths (migration/rebuild protection)
        // This MUST run before any sudo-dependent operations
        if tunEnabled || systemProxyEnabled {
            await PrivilegeService.shared.checkAndRepairSudoers()
        }

        // 3. Ensure privileges if TUN is enabled (or just general check)
        // If TUN is requested, we MUST have privileges ready before Clash launches
        if tunEnabled {
            clashViewModel.addLog("[Init] 🔐 Checking privileges for startup...")
            if !(await PrivilegeService.shared.checkPrivileges()) {
                if await PrivilegeService.shared.installSudoers() {
                    clashViewModel.addLog("[Init] ✅ Privileges installed")
                } else {
                    clashViewModel.addLog("[Init] ⚠️ Privilege installation failed - TUN might fail")
                }
            }
        }
    }
}
