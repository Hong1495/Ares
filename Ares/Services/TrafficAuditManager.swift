import SwiftUI
import Combine

/// Represents a traffic session for a specific application.
/// It persists even after the application exits or connections are closed.
nonisolated struct AppSession: Identifiable, Hashable, Sendable {
    let id: String              // Process Path (Aggregated Main Bundle) or "Unknown"
    let name: String            // Application Name
    let iconPath: String?       // Path to retrieve icon

    // Cumulative Totals (Monotonically increasing)
    var totalUpload: Int64 = 0
    var totalDownload: Int64 = 0

    // Real-time Status
    var activeConnectionCount: Int = 0
    var currentUploadSpeed: Int64 = 0
    var currentDownloadSpeed: Int64 = 0

    // Session State
    var lastActiveTime: Date = Date()
    var isRunning: Bool = false // Derived from system or connection presence

    // Child connections for drill-down view
    // Note: We only store *active* connections here to save memory.
    var activeConnections: [Connection] = []

    // History for Sparkline (Last 60 points of download speed)
    var speedHistory: [(Date, Int64)] = []

    static func == (lhs: AppSession, rhs: AppSession) -> Bool {
        lhs.id == rhs.id && lhs.activeConnections.count == rhs.activeConnections.count && lhs.speedHistory.count == rhs.speedHistory.count
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(activeConnections.count)
    }
}

/// Generic Group Node for non-App grouping (e.g. Proxy, Host)
nonisolated struct ActivityGroup: Identifiable, Hashable, Sendable {
    let id: String              // Unique ID (e.g. Proxy Name or Host)
    let title: String           // Display Title
    let icon: String            // SF Symbol Name
    let connections: [Connection] // Child connections

    // Aggregated Stats
    var upload: Int64 { connections.reduce(0) { $0 + $1.upload } }
    var download: Int64 { connections.reduce(0) { $0 + $1.download } }
    var uploadSpeed: Int64 { connections.reduce(0) { $0 + $1.uploadSpeed } }
    var downloadSpeed: Int64 { connections.reduce(0) { $0 + $1.downloadSpeed } }
    var activeCount: Int { connections.count }
}

/// Polymorphic Node for Hierarchical Table
nonisolated enum ActivityNode: Identifiable, Hashable, Sendable {
    case app(AppSession)
    case group(ActivityGroup)
    case connection(Connection)

    var id: String {
        switch self {
        case .app(let session): return "app_" + session.id
        case .group(let group): return "group_" + group.id
        case .connection(let conn): return "conn_" + conn.id
        }
    }

    var children: [ActivityNode]? {
        switch self {
        case .app(let session):
            return session.activeConnections.isEmpty ? nil : session.activeConnections.map { .connection($0) }
        case .group(let group):
            return group.connections.isEmpty ? nil : group.connections.map { .connection($0) }
        case .connection:
            return nil
        }
    }

    var sortValue: Int64 {
        switch self {
        case .app(let session): return session.currentDownloadSpeed
        case .group(let group): return group.downloadSpeed
        case .connection(let conn): return conn.downloadSpeed
        }
    }

    var title: String {
        switch self {
        case .app(let session): return session.name
        case .group(let group): return group.title
        case .connection(let conn): return conn.metadata.host.isEmpty ? conn.metadata.destinationIP : conn.metadata.host
        }
    }

    var icon: String? {
        switch self {
        case .app(let session): return session.iconPath
        case .group(let group): return group.icon
        case .connection: return nil
        }
    }
}

/// Background Actor for processing traffic data
actor TrafficAuditor {
    // Internal state for diffing
    private var sessionMap: [String: AppSession] = [:]
    private var connectionSnapshots: [String: (up: Int64, down: Int64)] = [:]
    private var lastUpdateTime: Date = Date()

    // Aggregates connections into sessions and calculates speeds
    func process(connections: [Connection]) -> [AppSession] {
        let now = Date()
        let timeDiff = now.timeIntervalSince(lastUpdateTime)
        let safeTimeDiff = timeDiff > 0 ? timeDiff : 1.0
        lastUpdateTime = now

        var touchList: Set<String> = []
        var appActiveConns: [String: [Connection]] = [:]
        var appDeltas: [String: (up: Int64, down: Int64)] = [:]

        for conn in connections {
            let identity = conn.identity
            let appKey = identity.key
            let prev = connectionSnapshots[conn.id] ?? (0, 0)
            let deltaUp = max(0, conn.upload - prev.up)
            let deltaDown = max(0, conn.download - prev.down)

            connectionSnapshots[conn.id] = (conn.upload, conn.download)

            if sessionMap[appKey] == nil {
                sessionMap[appKey] = AppSession(id: appKey, name: identity.name, iconPath: identity.iconPath)
            }

            sessionMap[appKey]?.totalUpload += deltaUp
            sessionMap[appKey]?.totalDownload += deltaDown
            sessionMap[appKey]?.lastActiveTime = now

            let currentDeltas = appDeltas[appKey] ?? (0, 0)
            appDeltas[appKey] = (currentDeltas.up + deltaUp, currentDeltas.down + deltaDown)

            touchList.insert(appKey)
            appActiveConns[appKey, default: []].append(conn)
        }

        // Cleanup Closed Connections
        let currentIDs = Set(connections.map { $0.id })
        let storedIDs = Set(connectionSnapshots.keys)
        let removedIDs = storedIDs.subtracting(currentIDs)
        for id in removedIDs {
            connectionSnapshots.removeValue(forKey: id)
        }

        // Update Sessions
        for key in sessionMap.keys {
            guard var session = sessionMap[key] else { continue }
            let isActiveInSnapshot = touchList.contains(key)

            session.activeConnections = appActiveConns[key] ?? []
            session.activeConnectionCount = session.activeConnections.count

            if let deltas = appDeltas[key] {
                session.currentUploadSpeed = Int64(Double(deltas.up) / safeTimeDiff)
                session.currentDownloadSpeed = Int64(Double(deltas.down) / safeTimeDiff)
            } else {
                session.currentUploadSpeed = 0
                session.currentDownloadSpeed = 0
            }

            session.speedHistory.append((now, session.currentDownloadSpeed))
            if session.speedHistory.count > 60 {
                session.speedHistory.removeFirst()
            }

            session.isRunning = isActiveInSnapshot
            sessionMap[key] = session
        }

        // Cleanup Stale Sessions (> 5 min inactive)
        let cleanupThreshold = now.addingTimeInterval(-300)
        let staleKeys = sessionMap.filter { $0.value.lastActiveTime < cleanupThreshold && !$0.value.isRunning }.map { $0.key }
        for key in staleKeys {
            sessionMap.removeValue(forKey: key)
        }

        // Return sorted list
        return sessionMap.values.sorted {
            if $0.isRunning != $1.isRunning { return $0.isRunning && !$1.isRunning }
            if $0.currentDownloadSpeed != $1.currentDownloadSpeed { return $0.currentDownloadSpeed > $1.currentDownloadSpeed }
            return $0.totalDownload > $1.totalDownload
        }
    }

    func reset() {
        sessionMap.removeAll()
        connectionSnapshots.removeAll()
    }

}


/// Singleton manager responsible for auditing traffic and maintaining app sessions.
@MainActor
final class TrafficAuditManager: ObservableObject {
    static let shared = TrafficAuditManager()

    @Published var sessions: [AppSession] = []

    // Background worker
    private let auditor = TrafficAuditor()

    private init() {}

    /// Process a new snapshot of active connections from the kernel.
    func update(with currentConnections: [Connection]) async {
        // Offload heavy processing to background actor
        let updatedSessions = await auditor.process(connections: currentConnections)

        // Update UI on MainActor
        self.sessions = updatedSessions
    }

    /// Reset all statistics
    func reset() {
        Task { await auditor.reset() }
        self.sessions = []
    }
}
