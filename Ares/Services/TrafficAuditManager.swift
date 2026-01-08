import SwiftUI
import Combine

/// Represents a traffic session for a specific application.
/// It persists even after the application exits or connections are closed.
struct AppSession: Identifiable, Hashable, Sendable {
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
    
    // History for Sparkline (Last 40 points of download speed)
    var speedHistory: [Int64] = []
    
    static func == (lhs: AppSession, rhs: AppSession) -> Bool {
        lhs.id == rhs.id && lhs.activeConnections.count == rhs.activeConnections.count && lhs.speedHistory == rhs.speedHistory
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(activeConnections.count)
    }
}

/// Generic Group Node for non-App grouping (e.g. Proxy, Host)
struct ActivityGroup: Identifiable, Hashable, Sendable {
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
enum ActivityNode: Identifiable, Hashable, Sendable {
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

/// Singleton manager responsible for auditing traffic and maintaining app sessions.
@MainActor
final class TrafficAuditManager: ObservableObject {
    static let shared = TrafficAuditManager()
    
    @Published var sessions: [AppSession] = []
    
    // Internal state for diffing
    // Map: ProcessPath -> AppSession
    private var sessionMap: [String: AppSession] = [:]
    
    // Map: ConnectionID -> (Upload, Download)
    private var connectionSnapshots: [String: (up: Int64, down: Int64)] = [:]
    
    private var lastUpdateTime: Date = Date()
    
    private init() {}
    
    // MARK: - Core Logic
    
    /// Process a new snapshot of active connections from the kernel.
    /// Updates cumulative totals and session states.
    func update(with currentConnections: [Connection]) {
        let now = Date()
        let timeDiff = now.timeIntervalSince(lastUpdateTime)
        let safeTimeDiff = timeDiff > 0 ? timeDiff : 1.0 // Avoid division by zero
        lastUpdateTime = now
        
        var touchList: Set<String> = [] // Track which apps are active in this snapshot
        
        // Temporary holding for grouping active connections by app and calculating period deltas
        var appActiveConns: [String: [Connection]] = [:]
        var appDeltas: [String: (up: Int64, down: Int64)] = [:]
        
        for conn in currentConnections {
            // OPTIMIZATION: Aggregate Helper Processes to Main App Bundle
            // e.g. "Google Chrome Helper" -> "Google Chrome"
            let appKey = findMainBundle(conn.metadata.processPath)
            
            // Calculate Delta
            let prev = connectionSnapshots[conn.id] ?? (0, 0)
            
            let deltaUp = max(0, conn.upload - prev.up)
            let deltaDown = max(0, conn.download - prev.down)
            
            // Update Snapshot
            connectionSnapshots[conn.id] = (conn.upload, conn.download)
            
            // Prepare or Get Session
            if sessionMap[appKey] == nil {
                let name = processName(from: appKey)
                sessionMap[appKey] = AppSession(
                    id: appKey,
                    name: name,
                    iconPath: appKey // Use aggregated bundle path for icon
                )
            }
            
            // Accumulate Traffic to Session (Historical Total)
            sessionMap[appKey]?.totalUpload += deltaUp
            sessionMap[appKey]?.totalDownload += deltaDown
            sessionMap[appKey]?.lastActiveTime = now
            
            // Accumulate Deltas for Speed Calculation (Speed in this window)
            let currentDeltas = appDeltas[appKey] ?? (0, 0)
            appDeltas[appKey] = (currentDeltas.up + deltaUp, currentDeltas.down + deltaDown)
            
            // Group for active list
            touchList.insert(appKey)
            appActiveConns[appKey, default: []].append(conn)
        }
        
        // 2. Cleanup Closed Connections from Snapshot Map
        let currentIDs = Set(currentConnections.map { $0.id })
        let storedIDs = Set(connectionSnapshots.keys)
        let removedIDs = storedIDs.subtracting(currentIDs)
        for id in removedIDs {
            connectionSnapshots.removeValue(forKey: id)
        }
        
        // 3. Update Session States (Running/Terminated)
        for key in sessionMap.keys {
            guard var session = sessionMap[key] else { continue }
            
            // Is it present in current snapshot?
            let isActiveInSnapshot = touchList.contains(key)
            
            // Update Active Connections List
            session.activeConnections = appActiveConns[key] ?? []
            session.activeConnectionCount = session.activeConnections.count
            
            // Update Speeds based on accumulated deltas in this time window
            var currentDownSpeed: Int64 = 0
            if let deltas = appDeltas[key] {
                session.currentUploadSpeed = Int64(Double(deltas.up) / safeTimeDiff)
                currentDownSpeed = Int64(Double(deltas.down) / safeTimeDiff)
                session.currentDownloadSpeed = currentDownSpeed
            } else {
                session.currentUploadSpeed = 0
                session.currentDownloadSpeed = 0
            }
            
            // Update History (Keep last 40 points)
            session.speedHistory.append(currentDownSpeed)
            if session.speedHistory.count > 40 {
                session.speedHistory.removeFirst()
            }
            
            // Determine "Running" State
            session.isRunning = isActiveInSnapshot
            
            sessionMap[key] = session
        }
        
        // 4. Publish sorted list
        // Sort: Active first, then by Download Speed (desc), then by Total Download
        self.sessions = sessionMap.values.sorted {
            if $0.isRunning != $1.isRunning {
                return $0.isRunning && !$1.isRunning
            }
            if $0.currentDownloadSpeed != $1.currentDownloadSpeed {
                return $0.currentDownloadSpeed > $1.currentDownloadSpeed
            }
            return $0.totalDownload > $1.totalDownload
        }
    }
    
    /// Reset all statistics
    func reset() {
        sessionMap.removeAll()
        self.sessions = []
    }
    
    // MARK: - Helper
    
    /// Finds the main app bundle path from a process path.
    /// E.g. /Applications/App.app/Contents/Helpers/Helper.app -> /Applications/App.app
    private func findMainBundle(_ path: String?) -> String {
        guard let path = path, !path.isEmpty else { return "Unknown" }
        
        // Fast path check: if not in an app bundle, return original
        if !path.contains(".app") {
            return path
        }
        
        let components = path.split(separator: "/")
        var currentPath = ""
        
        // Reconstruct path components
        for component in components {
            currentPath += "/" + component
            if component.hasSuffix(".app") {
                // Found the top-level app bundle
                return currentPath
            }
        }
        
        return path
    }
    
    private func processName(from path: String) -> String {
        guard !path.isEmpty && path != "Unknown" else { return "Unknown" }
        return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }
}
