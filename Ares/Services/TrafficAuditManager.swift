import Foundation
import Combine

/// Singleton manager responsible for auditing traffic and maintaining app sessions.
@MainActor
final class TrafficAuditManager: ObservableObject {
    static let shared = TrafficAuditManager()

    @Published var sessions: [AppSession] = []
    @Published private(set) var observedUpload: Int64 = 0
    @Published private(set) var observedDownload: Int64 = 0
    private var ledger = ActivityTrafficLedger()
    private var revision = UUID()

    // Background worker
    private let auditor = TrafficAuditor()

    private init() {}

    /// Process a new snapshot of active connections from the kernel.
    func update(with currentConnections: [Connection]) async {
        let expected = revision
        ledger.record(currentConnections)
        observedUpload = ledger.upload
        observedDownload = ledger.download
        // Offload heavy processing to background actor
        let updatedSessions = await auditor.process(connections: currentConnections)

        // Update UI on MainActor
        guard expected == revision else { return }
        self.sessions = updatedSessions
    }

    /// Reset all statistics
    func reset() async {
        revision = UUID()
        ledger.reset()
        observedUpload = 0
        observedDownload = 0
        await auditor.reset()
        self.sessions = []
    }
}
