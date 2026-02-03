import Foundation
import Combine

extension ClashController {
    func setupLifecycleObserver() {
        // Reactive Lifecycle: Only start monitoring when ClashService reports it is running
        statusSubscription = ClashViewModel.shared.$isRunning
            .combineLatest(ClashViewModel.shared.$isToggling)
            .receive(on: RunLoop.main)
            .sink { [weak self] isRunning, isToggling in
                if isRunning && !isToggling {
                    self?.consecutiveFailures = 0
                    // Add a tiny cool-down to ensure TCP ports are fully open by the kernel
                    Task {
                        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                        if let self = self, ClashViewModel.shared.isRunning, !ClashViewModel.shared.isToggling {
                            ClashViewModel.shared.addLog("[ClashController] 🟢 Core stable, activating monitors...")
                            if AppState.shared.isForeground {
                                self.startMonitors()
                            }
                        }
                    }
                } else {
                    if isToggling {
                        ClashViewModel.shared.addLog("[ClashController] 🟡 Toggling in progress, silencing monitors...")
                    }
                    self?.stopMonitors()
                }
            }
    }

    /// Start all monitors
    private func startMonitors() {
        // Trigger initial full sync IMMEDIATELY with retries
        Task { @MainActor in
            ClashViewModel.shared.addLog("[ClashController] 🔄 Initial state sync...")
            for i in 1...10 { // 10s window
                do {
                    try await self.fetchProxiesData()
                    try await self.fetchRules()
                    if let mode = try? await self.getCurrentMode() {
                        AppState.shared.currentMode = mode
                    }
                    ClashViewModel.shared.addLog("[ClashController] ✅ Initial sync completed (Attempt \(i))")
                    return
                } catch {
                    if i < 10 {
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                    }
                }
            }
        }

        // Start WebSocket for real-time traffic
        startTrafficMonitor()

        // Start polling for proxies - REMOVED: Managed by AppState heartbeat
/*
        stopRefreshTimer() // Safety clear
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                try? await self?.fetchProxiesData()
            }
        }
*/
    }

    /// Stop all monitors
    private func stopMonitors() {
        stopTrafficMonitor()
        stopRefreshTimer()
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    /// Dynamic Readiness Check: Polls the Clash API until it responds or timeouts.
    /// This is more elegant than a fixed Task.sleep().
    func waitForAPIReady(timeout: TimeInterval = 5.0) async -> Bool {
        let start = Date()
        let url = URL(string: "\(baseURL)/version")!

        while Date().timeIntervalSince(start) < timeout {
            do {
                let (_, response) = try await URLSession.shared.data(from: url)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    return true
                }
            } catch {
                // Ignore errors during retry period
            }
            // Wait briefly before retrying
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
        }
        return false
    }
}
