import Foundation
import Combine

extension ClashController {
    func setupLifecycleObserver() {
        // Reactive Lifecycle: Only start monitoring when ClashService reports it is running
        statusSubscription = ClashViewModel.shared.$runtimeState
            .combineLatest(ClashViewModel.shared.$isToggling)
            .receive(on: RunLoop.main)
            .sink { [weak self] runtimeState, isToggling in
                if runtimeState == .running && !isToggling {
                    self?.consecutiveFailures = 0
                    // Add a tiny cool-down to ensure TCP ports are fully open by the kernel
                    Task {
                        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                        if let self = self, ClashViewModel.shared.runtimeState == .running, !ClashViewModel.shared.isToggling {
                            self.startAutomaticLatencyTesting()
                            ClashViewModel.shared.addLog("[ClashController] 🟢 Core stable, activating monitors...")
                            if AppState.shared.isForeground {
                                self.startMonitors()
                            }
                        }
                    }
                } else if !runtimeState.isAPIReady || isToggling {
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
                    await self.monitorConnections()
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
        automaticLatencyTask?.cancel()
        automaticLatencyTask = nil
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
        guard let url = URL(string: "\(baseURL)/version") else { return false }

        while Date().timeIntervalSince(start) < timeout {
            do {
                try Task.checkCancellation()
                let remaining = timeout - Date().timeIntervalSince(start)
                guard remaining > 0 else { return false }
                let (_, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: min(1, remaining)))
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    return true
                }
            } catch is CancellationError {
                return false
            } catch {
                // Ignore errors during retry period
            }
            // Wait briefly before retrying
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
        }
        return false
    }
}
