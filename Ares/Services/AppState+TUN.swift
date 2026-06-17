import Combine
import Foundation

extension AppState {
    /// Toggle TUN mode (UI-facing, returns INSTANTLY)
    func toggleTUN() {
        clashViewModel.addLog("[TUN] Toggle requested", level: .debug)

        // 1. Double-guard: Check both local and ViewModel toggle state
        guard !isTUNToggling && !clashViewModel.isToggling else {
            clashViewModel.addLog("[TUN] Toggle rejected - already in progress", level: .warning)
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
        UserDefaults.standard.set(newTUN, forKey: DefaultsKeys.tunEnabled)

        // Update Controller Port IMMEDIATELY to avoid race conditions during toggle
        clashController.updatePort(tunEnabled: newTUN)

        clashViewModel.addLog("[TUN] 🔘 Switching to \(newTUN ? "TUN" : "Normal") mode...")

        // 3. Dispatch the heavy lifting to background
        Task.detached { [weak self] in
            guard let self = self else { return }

            let succeeded = await self.performTUNToggleWork(newState: newTUN)

            // 4. Cleanup on Main Thread
            await MainActor.run {
                if !succeeded {
                    self.tunEnabled = oldTUN
                    UserDefaults.standard.set(oldTUN, forKey: DefaultsKeys.tunEnabled)
                    self.clashController.updatePort(tunEnabled: oldTUN)
                    self.clashViewModel.addLog("[TUN] ❌ Mode switch failed, reverted to \(oldTUN ? "TUN" : "Normal") mode")
                }
                self.isTUNToggling = false
                self.clashViewModel.isToggling = false
                self.objectWillChange.send()
                if succeeded {
                    self.clashViewModel.addLog("[TUN] ✅ Mode switch completed")
                }
            }
        }
    }

    /// Perform actual TUN toggle work in background (nonisolated)
    nonisolated private func performTUNToggleWork(newState: Bool) async -> Bool {
        let viewModel = await MainActor.run {
            ClashViewModel.shared
        }

        await MainActor.run {
            viewModel.addLog("[TUN] 🔄 Restarting Clash for \(newState ? "TUN" : "Normal") mode...")
        }

        // 1. Ensure privileges (Sudoers)
        let hasPrivileges = await PrivilegeService.shared.checkPrivileges()
        if !hasPrivileges {
            _ = await PrivilegeService.shared.installSudoers()
        }
        guard await PrivilegeService.shared.checkPrivileges() else {
            await MainActor.run {
                viewModel.addLog("[TUN] ❌ Administrator privileges unavailable")
            }
            return false
        }

        // 2. Stop old process thoroughly
        await viewModel.stopCore(intendedRestart: true)

        // 3. Start with new TUN config
        await viewModel.startCore(isRestart: true)

        // 4. startCore only reports running after Clash API is ready.
        let isReady = await MainActor.run {
            viewModel.runtimeState.isAPIReady
        }
        if !isReady {
            await MainActor.run {
                viewModel.addLog("[TUN] ⚠️ Clash API is not ready after restart")
            }
            return false
        } else {
            await MainActor.run {
                viewModel.addLog("[TUN] ⚡️ Clash API is ready")
            }
        }

        // 5. Update system proxy if needed
        let proxyEnabled = await MainActor.run { AppState.shared.systemProxyEnabled }
        if proxyEnabled && isReady {
            await AppState.shared.enableSystemProxy()
        } else if proxyEnabled {
            await MainActor.run {
                viewModel.addLog("[TUN] ⚠️ System proxy restore skipped because Clash API is not ready")
            }
            return false
        }

        // 6. Final verification - non-blocking but ensures state is correct
        try? await self.verifyTUNStatus()
        return true
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
}
