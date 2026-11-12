import Foundation

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
        case .app(let session): return session.totalDownload
        case .group(let group): return group.download
        case .connection(let conn): return conn.download
        }
    }

    var uploadSortValue: Int64 {
        switch self {
        case .app(let session): return session.totalUpload
        case .group(let group): return group.upload
        case .connection(let conn): return conn.upload
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

