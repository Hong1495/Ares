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
        await PrivilegeService.shared.checkAndRepairSudoers()

        // 3. Ensure privileges if TUN is enabled (or just general check)
        // If TUN is requested, we MUST have privileges ready before Clash launches
        var shouldCheckPrivileges = tunEnabled
        if !shouldCheckPrivileges {
            // Even if TUN is off, we might want to check for future toggle speed,
            // but let's check if we don't have them
            shouldCheckPrivileges = !(await PrivilegeService.shared.checkPrivileges())
        }

        if shouldCheckPrivileges {
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
