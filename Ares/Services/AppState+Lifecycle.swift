import Foundation

extension AppState {
    // MARK: - Service Lifecycle Management

    func systemWillSleep() {
        systemIsSleeping = true
        wakeVerificationTask?.cancel()
        clashController.stopTrafficMonitor()
    }

    /// Waking does not blindly relaunch a second core or rewrite system proxy preferences.
    func systemDidWake() {
        systemIsSleeping = false
        wakeVerificationTask?.cancel()
        wakeVerificationTask = Task { @MainActor in
            for _ in 0..<30 {
                if Task.isCancelled { return }
                if !self.clashViewModel.isToggling && self.operationStatus == nil { break }
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            }
            guard !Task.isCancelled, !self.systemIsSleeping, !self.clashViewModel.isToggling,
                  self.operationStatus == nil, self.clashViewModel.runtimeState.isAPIReady else { return }
            let generation = self.clashController.runtimeGeneration
            var ready = false
            for _ in 0..<3 {
                do {
                    let data = try await self.clashController.readRuntimeConfiguration()
                    try CoreAPIContract.verifyTUN(data, expected: self.tunEnabled)
                    ready = true
                    break
                } catch {
                    do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                }
            }
            guard !Task.isCancelled, generation == self.clashController.runtimeGeneration,
                  !self.systemIsSleeping, !self.clashViewModel.isToggling, self.operationStatus == nil else { return }
            if ready {
                if self.isForeground { self.clashController.startTrafficMonitor() }
                self.syncStatus()
            } else {
                self.reportError("The core did not respond after wake. Check its status before reconnecting.")
            }
        }
    }

    /// Global "Wake Up" - Called when App enters Foreground
    func wakeUp() {
        if isForeground && didSendInitialWake { return }
        clashViewModel.addLog("[AppState] Waking up services", level: .debug)
        isForeground = true
        animationsEnabled = true
        didSendInitialWake = true

        // Broadcast Wake Up
        NotificationCenter.default.post(name: .appDidWakeUp, object: nil)

        // 1. Resume Traffic Monitoring
        if !systemIsSleeping && clashViewModel.isRunning {
            clashController.startTrafficMonitor()
        }

        // 2. Resume Heartbeat
        // Note: Polling timer is auto-connected, but we ensured strictly valid execution
        // We could force a sync immediately here
        syncStatus()
    }

    /// Global "Go Silent" - Called when App enters Background
    func goSilent() {
        guard isForeground else { return }
        clashViewModel.addLog("[AppState] Going silent", level: .debug)
        isForeground = false
        animationsEnabled = false

        // Broadcast Silence
        NotificationCenter.default.post(name: .appDidGoSilent, object: nil)

        // 1. Hard Stop Traffic Monitoring (Close Socket)
        clashController.stopTrafficMonitor()

        // 2. Stop Connections Monitoring (Will be handled by View onDisappear, but double check?)
        // ConnectionsViewModel is StateObject in View, so it handles itself via View lifecycle.
        // But preventing Global Polling is key.
    }
}
