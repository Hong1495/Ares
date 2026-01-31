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
        case policies
        case connections
        case analysis
        case topology
        case routeMap
        case logs
        case settings

        var displayName: String {
            switch self {
            case .dashboard: return "Dashboard"
            case .policies: return "Policies"
            case .connections: return "Activity"
            case .analysis: return "Analysis"
            case .topology: return "Topology"
            case .routeMap: return "Routing"
            case .logs: return "Logs"
            case .settings: return "Settings"
            }
        }
    }
    @Published var selection: NavigationItem = .dashboard

    // System toggles
    @Published var systemProxyEnabled = false
    @Published var tunEnabled = false

    // IP Information (Shared across components)
    @Published var publicIP: String = "Fetching..."
    @Published var countryCode: String?

    // Toggle state guards to prevent race conditions during fast switching
    private var isMITMToggling = false
    private var isTUNToggling = false
    private var isSystemProxyToggling = false

    // Computed property for UI binding
    var mitmEnabled: Bool {
        NetworkMITMService.shared.isRunning
    }

    // Statistics
    @Published var activeConnectionsCount = 0

    private var clashController = ClashController.shared
    private var clashViewModel = ClashViewModel.shared
    private var systemProxyManager = SystemProxyManager.shared
    private var browserAnalysisService = BrowserAnalysisService.shared

    private var pollingTimer: AnyCancellable?

    private init() {
        // Restore properties synchronously where possible
        tunEnabled = UserDefaults.standard.bool(forKey: "tunEnabled")

        // Start polling timer (Unified Heartbeat)
        // 降低轮询频率：从 3 秒改为 10 秒以减少 CPU 占用
        pollingTimer = Timer.publish(every: 10.0, on: .main, in: .common)
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

        // 1. Sync preferences and system state (No network calls yet)
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

        // 3. Monitor connections count
        await clashController.monitorConnections()
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

        // CRITICAL: If disabling proxy while MITM is running, stop MITM first to avoid crashes
        if !newState && NetworkMITMService.shared.isRunning {
            clashViewModel.addLog("[AppState] ⚠️ MITM is running - stopping MITM before disabling system proxy")
            await NetworkMITMService.shared.stop()
        }

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

        // Determine correct ports and rules
        let (httpPort, socksPort) = getProxyPorts()
        var bypassRules = UserDefaults.standard.string(forKey: "bypassRules") ?? ""

        // CRITICAL: Ensure local traffic is bypassed for Browser Analysis Extension
        let localBypasses = ["127.0.0.1", "localhost"]
        for bypass in localBypasses {
            if !bypassRules.contains(bypass) {
                if !bypassRules.isEmpty && !bypassRules.hasSuffix(",") {
                    bypassRules += ", "
                }
                bypassRules += bypass
            }
        }

        guard await systemProxyManager.setSystemProxy(enabled: newState, httpPort: httpPort, socksPort: socksPort, bypassRules: bypassRules) else {
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



    /// Toggle TUN mode
    /// Toggle TUN mode (UI-facing, returns INSTANTLY)
    func toggleTUN() {
        print("[AppState] ⚡️ ENTERED toggleTUN()")

        // 1. Double-guard: Check both local and ViewModel toggle state
        guard !isTUNToggling && !clashViewModel.isToggling else {
            print("[AppState] 🚫 Toggle rejected - already in progress")
            return
        }

        // 2. IMMEDIATE Synchronous Locking & UI Update
        isTUNToggling = true // Local guard
        clashViewModel.isToggling = true // Global guard for UI
        clashViewModel.objectWillChange.send()

        let oldTUN = tunEnabled
        let newTUN = !oldTUN
        tunEnabled = newTUN

        // Persist immediately
        UserDefaults.standard.set(newTUN, forKey: "tunEnabled")

        // Update Controller Port IMMEDIATELY to avoid race conditions during toggle
        clashController.updatePort(tunEnabled: newTUN)

        clashViewModel.addLog("[TUN] 🔘 Switching to \(newTUN ? "TUN" : "Normal") mode...")

        // 3. Dispatch the heavy lifting to background
        Task.detached { [weak self] in
            guard let self = self else { return }

            await self.performTUNToggleWork(newState: newTUN)

            // 4. Cleanup on Main Thread
            await MainActor.run {
                self.isTUNToggling = false
                self.clashViewModel.isToggling = false
                self.objectWillChange.send()
                self.clashViewModel.addLog("[TUN] ✅ Mode switch completed")
            }
        }
    }

    /// Perform actual TUN toggle work in background (nonisolated)
    nonisolated private func performTUNToggleWork(newState: Bool) async {
        let (viewModel, controller) = await MainActor.run {
            (ClashViewModel.shared, ClashController.shared)
        }

        await MainActor.run {
            viewModel.addLog("[TUN] 🔄 Restarting Clash for \(newState ? "TUN" : "Normal") mode...")
        }

        // 1. Ensure privileges (Sudoers)
        let hasPrivileges = await PrivilegeService.shared.checkPrivileges()
        if !hasPrivileges {
            _ = await PrivilegeService.shared.installSudoers()
        }

        // 2. Stop old process thoroughly
        await viewModel.stopCore(intendedRestart: true)

        // 3. Start with new TUN config
        await viewModel.startCore(isRestart: true)

        // 4. ELEGANT: Dynamic Readiness Check (Poll API until responsive)
        let isReady = await controller.waitForAPIReady(timeout: 5.0)
        if !isReady {
            await MainActor.run {
                viewModel.addLog("[TUN] ⚠️ Clash API failed to respond within timeout")
            }
        } else {
            await MainActor.run {
                viewModel.addLog("[TUN] ⚡️ Clash API is ready")
            }
        }

        // 5. Update system proxy if needed
        let proxyEnabled = await MainActor.run { AppState.shared.systemProxyEnabled }
        if proxyEnabled {
            await AppState.shared.enableSystemProxy()
        }

        // 6. Final verification - non-blocking but ensures state is correct
        try? await self.verifyTUNStatus()
    }



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

    /// Verify TUN status from Clash API
    nonisolated private func verifyTUNStatus() async throws {
        let (baseURL, expectedTUN) = await MainActor.run {
            (ClashController.shared.baseURL, AppState.shared.tunEnabled)
        }

        guard let url = URL(string: "\(baseURL)/configs") else {
            throw NSError(domain: "AppState", code: 1)
        }

        guard let (data, _) = try? await URLSession.shared.data(from: url) else {
            // Quiet fail - API might not be ready yet even after start
            return
        }
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            await MainActor.run {
                ClashViewModel.shared.addLog("[TUN] ⚠️ Failed to parse API config response")
            }
            return
        }

        if let tun = json["tun"] as? [String: Any] {
            let enabled = tun["enable"] as? Bool ?? false
            let stack = tun["stack"] as? String ?? "unknown"

            await MainActor.run {
                let vm = ClashViewModel.shared
                vm.addLog("[TUN] 📊 Clash API Status:")
                vm.addLog("[TUN]   - Enable: \(enabled)")
                vm.addLog("[TUN]   - Stack: \(stack)")

                if enabled != expectedTUN {
                    vm.addLog("[TUN] ⚠️ WARNING: State mismatch! Expected=\(expectedTUN), Actual=\(enabled)")
                }
            }
        } else {
            await MainActor.run {
                ClashViewModel.shared.addLog("[TUN] ⚠️ No TUN config found in Clash response")
            }
        }
    }

    /// Force enable system proxy (for startup restoration)
    func enableSystemProxy() async {
        clashViewModel.addLog("[AppState] 🔄 Restoring system proxy state...")

        // Ensure privileges
        if !(await PrivilegeService.shared.checkPrivileges()) {
             _ = await PrivilegeService.shared.installSudoers()
        }

        // Determine correct ports and rules
        let (httpPort, socksPort) = getProxyPorts()
        var bypassRules = UserDefaults.standard.string(forKey: "bypassRules") ?? ""

        // CRITICAL: Ensure local traffic is bypassed for Browser Analysis Extension
        let localBypasses = ["127.0.0.1", "localhost"]
        for bypass in localBypasses {
            if !bypassRules.contains(bypass) {
                if !bypassRules.isEmpty && !bypassRules.hasSuffix(",") {
                    bypassRules += ", "
                }
                bypassRules += bypass
            }
        }

        if await systemProxyManager.setSystemProxy(enabled: true, httpPort: httpPort, socksPort: socksPort, bypassRules: bypassRules) {
            systemProxyEnabled = true
            objectWillChange.send()
            clashViewModel.addLog("[AppState] ✅ System proxy enabled (HTTP/HTTPS: \(httpPort), SOCKS: \(socksPort))")
        } else {
            clashViewModel.addLog("[AppState] ❌ Failed to restore system proxy")
        }
    }

    /// Helper to get proxy ports based on TUN mode state
    private func getProxyPorts() -> (Int, Int) {
        let defaults = UserDefaults.standard
        let clashHttpPort = Int(defaults.string(forKey: "mixedPort") ?? "7890") ?? 7890
        let clashSocksPort = Int(defaults.string(forKey: "socksPort") ?? "7891") ?? 7891

        // In TUN mode: System proxy points to Clash with isolated ports
        // Matching logic in ClashConfig.swift:
        // actualMixedPort = 17890 (HTTP/Mixed)
        // actualSocksPort = 17891 (SOCKS)
        if tunEnabled {
            return (17890, 17891)
        }

        // In non-TUN mode: If MITM is running, system proxy points to MITM
        // Traffic flows SystemProxy->MITM->Clash
        if NetworkMITMService.shared.isRunning {
            let mitmPort = Int(NetworkMITMService.shared.currentPort)
            let httpPort = mitmPort > 0 ? mitmPort : clashHttpPort
            // SOCKS still goes to Clash (MITM doesn't handle SOCKS)
            return (httpPort, clashSocksPort)
        }

        // Default: System proxy points to Clash
        return (clashHttpPort, clashSocksPort)
    }

    /// Update shared IP info
    func updateIPInfo(ip: String, country: String?) {
        self.publicIP = ip
        self.countryCode = country
    }
}
