import Combine
import Foundation

extension AppState {
    /// Toggle system proxy
    func toggleSystemProxy() async {
        guard !isSystemProxyToggling, beginOperation("Updating System Proxy") else {
            clashViewModel.addLog("[AppState] ⚠️ System proxy toggle ignored - already in progress")
            return
        }

        isSystemProxyToggling = true
        defer {
            isSystemProxyToggling = false
            if operationStatus != nil {
                finishOperation()
            }
        }

        let newState = !systemProxyEnabled
        clashViewModel.addLog("[AppState] 🌐 \(newState ? "Enabling" : "Disabling") system proxy...")

        // Never point macOS at a local proxy until the core is ready to accept traffic.
        if newState && !clashViewModel.isRunning {
            await clashViewModel.start()
            guard clashViewModel.isRunning else {
                finishOperation(error: "System Proxy was not enabled because the Clash core failed to start")
                return
            }
        }

        if newState {
            guard clashViewModel.runtimeState.isAPIReady,
                  clashViewModel.appliedProfileRevision == ProfileService.shared.activeProfileRevision else {
                finishOperation(error: "Apply the selected subscription before enabling System Proxy.")
                return
            }
        }

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
        var bypassRules = UserDefaults.standard.string(forKey: DefaultsKeys.bypassRules) ?? ""

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
            finishOperation(error: systemProxyManager.lastError ?? "System Proxy update could not be verified.")
            return
        }

        systemProxyEnabled = newState
        UserDefaults.standard.set(newState, forKey: DefaultsKeys.systemProxyEnabled) // Save preference
        clashViewModel.addLog("[AppState] ✅ System proxy \(newState ? "enabled" : "disabled") (HTTP/HTTPS: \(httpPort), SOCKS: \(socksPort))")


    }

    /// Force enable system proxy (for startup restoration)
    @discardableResult
    func enableSystemProxy(expectedRevision: String? = nil) async -> Bool {
        guard clashViewModel.runtimeState.isAPIReady,
              clashViewModel.appliedProfileRevision == (expectedRevision ?? ProfileService.shared.activeProfileRevision) else {
            reportError("System Proxy was not enabled: the selected subscription and core are not ready.")
            return false
        }
        clashViewModel.addLog("[AppState] 🔄 Restoring system proxy state...")

        // Ensure privileges
        if !(await PrivilegeService.shared.checkPrivileges()) {
            _ = await PrivilegeService.shared.installSudoers()
        }

        // Determine correct ports and rules
        let (httpPort, socksPort) = getProxyPorts()
        var bypassRules = UserDefaults.standard.string(forKey: DefaultsKeys.bypassRules) ?? ""

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
            clashViewModel.addLog("[AppState] ✅ System proxy enabled (HTTP/HTTPS: \(httpPort), SOCKS: \(socksPort))")
            return true
        } else {
            clashViewModel.addLog("[AppState] ❌ Failed to restore system proxy")
            reportError(systemProxyManager.lastError ?? "Failed to restore System Proxy")
            return false
        }
    }

    /// Helper to get proxy ports based on TUN mode state
    private func getProxyPorts() -> (Int, Int) {
        let defaults = UserDefaults.standard
        let clashHttpPort = clashViewModel.verifiedMixedPort ?? Int(defaults.string(forKey: DefaultsKeys.mixedPort) ?? "\(ClashPorts.defaultMixed)") ?? ClashPorts.defaultMixed
        let clashSocksPort = clashViewModel.verifiedSocksPort ?? Int(defaults.string(forKey: DefaultsKeys.socksPort) ?? "\(ClashPorts.defaultSocks)") ?? ClashPorts.defaultSocks

        // In TUN mode: System proxy points to Clash with isolated ports
        // Matching logic in ClashConfig.swift:
        // actualMixedPort = 17890 (HTTP/Mixed)
        // actualSocksPort = 17891 (SOCKS)
        if tunEnabled {
            return (ClashPorts.tunMixed, ClashPorts.tunSocks)
        }

        // In non-TUN mode: If MITM is running, system proxy points to MITM
        // Traffic flows SystemProxy->MITM->Clash
        if NetworkMITMService.shared.isRunning && NetworkMITMService.shared.routingEnabled {
            let mitmPort = Int(NetworkMITMService.shared.currentPort)
            let httpPort = mitmPort > 0 ? mitmPort : clashHttpPort
            // SOCKS still goes to Clash (MITM doesn't handle SOCKS)
            return (httpPort, clashSocksPort)
        }

        // Default: System proxy points to Clash
        return (clashHttpPort, clashSocksPort)
    }
}
