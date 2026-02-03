import Foundation

extension AppState {
    // MARK: - Service Lifecycle Management

    /// Global "Wake Up" - Called when App enters Foreground
    func wakeUp() {
        if isForeground && didSendInitialWake { return }
        print("[AppState] ☀️ Waking up services...")
        isForeground = true
        animationsEnabled = true
        didSendInitialWake = true

        // Broadcast Wake Up
        NotificationCenter.default.post(name: .appDidWakeUp, object: nil)

        // 1. Resume Traffic Monitoring
        if clashViewModel.isRunning {
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
        print("[AppState] 🌙 Going silent (Background)...")
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
