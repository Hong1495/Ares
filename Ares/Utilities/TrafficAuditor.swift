import Foundation

/// Background Actor for processing traffic data
actor TrafficAuditor {
    // Internal state for diffing
    private var sessionMap: [String: AppSession] = [:]
    private var connectionSnapshots: [String: (up: Int64, down: Int64)] = [:]
    private var measuredIDs = Set<String>()
    private var lastUpdateTime: Date = Date()

    // Aggregates connections into sessions and calculates speeds
    func process(connections: [Connection], now: Date = Date()) -> [AppSession] {
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
            // The first observation includes lifetime bytes, not one interval of speed.
            let measured = measuredIDs.contains(conn.id)
            appDeltas[appKey] = (currentDeltas.up + (measured ? deltaUp : 0), currentDeltas.down + (measured ? deltaDown : 0))
            measuredIDs.insert(conn.id)

            touchList.insert(appKey)
            appActiveConns[appKey, default: []].append(conn)
        }

        // Keep byte baselines when a connection temporarily disappears from a sample.

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

        // Keep inactive application totals for this observation session so row
        // totals remain consistent with the cumulative header, until explicit reset.
        // Return sorted list
        return sessionMap.values.sorted {
            if $0.isRunning != $1.isRunning { return $0.isRunning && !$1.isRunning }
            if $0.currentDownloadSpeed != $1.currentDownloadSpeed { return $0.currentDownloadSpeed > $1.currentDownloadSpeed }
            return $0.totalDownload > $1.totalDownload
        }
    }

    func reset() {
        sessionMap.removeAll()
        // Retain live-connection baselines across a statistics reset.
    }

}


