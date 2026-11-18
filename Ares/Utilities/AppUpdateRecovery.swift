import Foundation

/// Sparkle owns the regular schedule. This only tracks bounded retries after a
/// failed feed request; a valid feed or disabling automatic checks resets it.
struct AppUpdateRecovery {
    static let checkInterval: TimeInterval = 60 * 60
    private let retryDelays: [TimeInterval]
    private let reconnectDelay: TimeInterval
    private(set) var needsRecovery = false
    private(set) var retryAt: Date?
    private var failures = 0
    private var lastAttempt: Date?

    init(retryDelays: [TimeInterval] = [60, 300, 900], reconnectDelay: TimeInterval = 60) {
        self.retryDelays = retryDelays
        self.reconnectDelay = reconnectDelay
    }

    mutating func checkStarted(at now: Date) {
        lastAttempt = now
        retryAt = nil
    }

    mutating func feedFailed(at now: Date) {
        needsRecovery = true
        retryAt = failures < retryDelays.count ? now.addingTimeInterval(retryDelays[failures]) : nil
        failures += 1
    }

    mutating func reset() {
        needsRecovery = false
        retryAt = nil
        failures = 0
    }

    mutating func networkRestored(at now: Date) {
        guard needsRecovery else { return }
        // Network-path notifications can arrive in bursts while a VPN starts.
        let earliest = max(now, (lastAttempt ?? now).addingTimeInterval(reconnectDelay))
        retryAt = min(retryAt ?? earliest, earliest)
    }

    func regularCheckIsOverdue(lastCheck: Date?, now: Date) -> Bool {
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) >= Self.checkInterval
    }
}
