import Combine
import Foundation

extension AppState {
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
        UserDefaults.standard.set(newTUN, forKey: DefaultsKeys.tunEnabled)

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
