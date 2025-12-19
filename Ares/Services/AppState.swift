import Foundation
import Combine

/// Global application state for synchronization across all views
@MainActor
class AppState: ObservableObject {
    static let shared = AppState()
    
    // Clash Mode
    @Published var currentMode: ClashConfig.Mode = .rule
    
    // Navigation State
    enum NavigationItem: Hashable {
        case dashboard
        case proxies
        case profiles
        case connections
        case logs
        case antigravity
        case rules
        case settings
    }
    @Published var selection: NavigationItem = .dashboard
    
    // System toggles
    @Published var systemProxyEnabled = false
    @Published var tunEnabled = false
    
    // Statistics
    @Published var activeConnectionsCount = 0
    
    private var clashController = ClashController.shared
    private var clashViewModel = ClashViewModel.shared
    private var systemProxyManager = SystemProxyManager.shared
    
    private var pollingTimer: AnyCancellable?
    
    private init() {
        // Restore properties synchronously where possible
        tunEnabled = UserDefaults.standard.bool(forKey: "tunEnabled")
        
        // Start polling timer
        pollingTimer = Timer.publish(every: 2.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task {
                    self?.syncStatus()
                }
            }
    }
    
    /// Async initialization sequence
    func initialize() async {
        clashViewModel.addLog("[AppState] 🚀 Initializing application state...")
        
        // 1. Sync connection status
        await syncWithClash()
        
        // 2. Check system proxy status (Prefer saved preference)
        systemProxyEnabled = UserDefaults.standard.bool(forKey: "systemProxyEnabled")
        // Check actual system state only if preference is missing? No, user preference dictates action.
        // If user wants it ON, we will enforce it later in AresApp.
        
        // 3. Ensure privileges if TUN is enabled (or just general check)
        // If TUN is requested, we MUST have privileges ready before Clash launches
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
    
    /// Sync status from services
    func syncStatus() {
        // Only sync if we are NOT in the middle of a restart operation
        _ = clashViewModel.isRunning
    }
    
    /// Sync state from Clash API
    func syncWithClash() async {
        // Fetch current mode
        if let mode = try? await clashController.getCurrentMode() {
            currentMode = mode
        }
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
    
    // State Guard for System Proxy
    private var isSystemProxyToggling = false

    /// Toggle system proxy
    func toggleSystemProxy() async {
        guard !isSystemProxyToggling else {
            clashViewModel.addLog("[AppState] ⚠️ System proxy toggle ignored - already in progress")
            return
        }
        
        isSystemProxyToggling = true
        defer { isSystemProxyToggling = false }
        
        let newState = !systemProxyEnabled
        clashViewModel.addLog("[AppState] 🌐 \(newState ? "Enabling" : "Disabling") system proxy...")
        
        // Optimistic Update
        systemProxyEnabled = newState
        objectWillChange.send()
        
        // Ensure privileges are installed if missing (Auto-Upgrade)
        var shouldCheckPrivileges = false
        if newState {
            shouldCheckPrivileges = !(await PrivilegeService.shared.checkPrivileges())
        }
        
        if shouldCheckPrivileges {
             clashViewModel.addLog("[SystemProxy] 🔐 Installing privilege helper...")
             _ = await PrivilegeService.shared.installSudoers()
        }
        
        // Use correct ports based on TUN mode
        let httpPort: Int
        let socksPort: Int
        
        if tunEnabled {
            // TUN mode uses fixed high ports (port isolation)
            httpPort = 17890
            socksPort = 17891
        } else {
            // Normal mode uses user-configured ports
            let defaults = UserDefaults.standard
            httpPort = Int(defaults.string(forKey: "mixedPort") ?? "7890") ?? 7890
            socksPort = Int(defaults.string(forKey: "socksPort") ?? "7891") ?? 7891
        }
        
        guard await systemProxyManager.setSystemProxy(enabled: newState, httpPort: httpPort, socksPort: socksPort) else {
            clashViewModel.addLog("[AppState] ❌ Failed to set system proxy")
            // Revert on failure
            systemProxyEnabled = !newState
            return
        }
        
        UserDefaults.standard.set(newState, forKey: "systemProxyEnabled") // Save preference
        clashViewModel.addLog("[AppState] ✅ System proxy \(newState ? "enabled" : "disabled") (HTTP/HTTPS: \(httpPort), SOCKS: \(socksPort))")
        
        // Start Clash if it's not running and we just enabled proxy
        if newState && !clashViewModel.isRunning {
            await clashViewModel.start()
        } else if !newState && !tunEnabled {
            // Keep running to avoid side effects
        }
    }
    
    // State Guard
    private var isToggling = false

    /// Toggle TUN mode
    /// Toggle TUN mode (UI-facing, returns INSTANTLY)
    func toggleTUN() {
        print("[AppState] ⚡️ ENTERED toggleTUN()")
        
        guard !isToggling else {
            print("[AppState] 🚫 Toggle rejected - already in progress")
            return
        }
        
        // IMMEDIATELY dispatch to background - don't touch ANY state here!
        Task.detached { [weak self] in
            guard let self = self else { return }
            
            // Get current state and update UI on MainActor
            let newState = await MainActor.run {
                self.isToggling = true
                let current = self.tunEnabled
                self.tunEnabled = !current
                self.objectWillChange.send()
                return !current
            }
            
            // Save to UserDefaults in background
            UserDefaults.standard.set(newState, forKey: "tunEnabled")
            await self.performTUNToggleWork(newState: newState)
            
            // Reset toggling flag
            await MainActor.run {
                self.isToggling = false
            }
        }
    }
    
    /// Perform actual TUN toggle work in background (nonisolated)
    nonisolated private func performTUNToggleWork(newState: Bool) async {
        let viewModel = await MainActor.run { ClashViewModel.shared }
        
        await MainActor.run {
            viewModel.addLog("[TUN] 🔄 Toggling TUN mode to: \(newState ? "ENABLED" : "DISABLED")")
        }
        
        // Check and install privileges if needed
        let hasPrivileges = await PrivilegeService.shared.checkPrivileges()
        if !hasPrivileges {
            await MainActor.run {
                viewModel.addLog("[TUN] 🔐 Installing privilege helper...")
            }
            if await PrivilegeService.shared.installSudoers() {
                await MainActor.run {
                    viewModel.addLog("[TUN] ✅ Privileges granted")
                }
            } else {
                await MainActor.run {
                    viewModel.addLog("[TUN] ⚠️ Failed to grant privileges, cleanup might fail")
                }
            }
        }
        
        await MainActor.run {
            viewModel.addLog("[TUN] 🔄 Restarting Clash...")
        }
        
        // Stop old process - use ClashViewModel delegation
        await viewModel.stop(intendedRestart: true)
        
        // Start with new TUN config
        await viewModel.start(isRestart: true)
        
        // CRITICAL: Update system proxy ports to match new mode
        let proxyEnabled = await MainActor.run { self.systemProxyEnabled }
        if proxyEnabled {
            await MainActor.run {
                viewModel.addLog("[TUN] 🔄 Updating system proxy for new mode...")
            }
            await self.enableSystemProxy()  // This will use correct ports based on new tunEnabled state
        }
        
        await MainActor.run {
            viewModel.addLog("[TUN] ✅ TUN mode \(newState ? "enabled" : "disabled") successfully")
        }
        
        // Verify in background
        let serviceIsRunning = await MainActor.run { viewModel.isRunning }
        if serviceIsRunning {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            try? await self.verifyTUNStatus()
        }
    }
    
    /// Verify TUN status from Clash API
    private func verifyTUNStatus() async throws {
        guard let url = URL(string: "http://127.0.0.1:9097/configs") else {
            throw NSError(domain: "AppState", code: 1)
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        
        if let tun = json["tun"] as? [String: Any] {
            let enabled = tun["enable"] as? Bool ?? false
            let stack = tun["stack"] as? String ?? "unknown"
            
            clashViewModel.addLog("[TUN] 📊 Clash API Status:")
            clashViewModel.addLog("[TUN]   - Enable: \(enabled)")
            clashViewModel.addLog("[TUN]   - Stack: \(stack)")
            
            if enabled != tunEnabled {
                clashViewModel.addLog("[TUN] ⚠️ WARNING: State mismatch! Expected=\(tunEnabled), Actual=\(enabled)")
            }
        } else {
            clashViewModel.addLog("[TUN] ⚠️ No TUN config found in Clash response")
        }
    }

    /// Force enable system proxy (for startup restoration)
    func enableSystemProxy() async {
        clashViewModel.addLog("[AppState] 🔄 Restoring system proxy state...")
        
        // Ensure privileges
        if !(await PrivilegeService.shared.checkPrivileges()) {
             _ = await PrivilegeService.shared.installSudoers()
        }
        
        // Use correct ports based on TUN mode
        let httpPort: Int
        let socksPort: Int
        
        if tunEnabled {
            // TUN mode uses fixed high ports (port isolation)
            httpPort = 17890
            socksPort = 17891
        } else {
            // Normal mode uses user-configured ports
            let defaults = UserDefaults.standard
            httpPort = Int(defaults.string(forKey: "mixedPort") ?? "7890") ?? 7890
            socksPort = Int(defaults.string(forKey: "socksPort") ?? "7891") ?? 7891
        }
        
        if await systemProxyManager.setSystemProxy(enabled: true, httpPort: httpPort, socksPort: socksPort) {
            systemProxyEnabled = true
            objectWillChange.send()
            clashViewModel.addLog("[AppState] ✅ System proxy enabled (HTTP/HTTPS: \(httpPort), SOCKS: \(socksPort))")
        } else {
            clashViewModel.addLog("[AppState] ❌ Failed to restore system proxy")
        }
    }
}
