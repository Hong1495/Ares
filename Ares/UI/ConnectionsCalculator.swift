import Foundation

actor ConnectionsCalculator {
    private var previousSnapshots: [String: (up: Int64, down: Int64, time: Date)] = [:]

    func process(rawConnections: [Connection], appSessions: [AppSession], groupingMode: GroupingMode, now: Date = Date()) -> (connections: [Connection], nodes: [ActivityNode]) {

        // 1. Calculate Speeds
        var computedConnections = rawConnections
        for i in 0..<computedConnections.count {
            let conn = computedConnections[i]
            if let prev = previousSnapshots[conn.id] {
                let timeDiff = now.timeIntervalSince(prev.time)
                if timeDiff > 0 {
                    computedConnections[i].uploadSpeed = Int64(Double(max(0, conn.upload - prev.up)) / timeDiff)
                    computedConnections[i].downloadSpeed = Int64(Double(max(0, conn.download - prev.down)) / timeDiff)
                }
            }
        }

        // Update Snapshots
        var newSnapshots: [String: (up: Int64, down: Int64, time: Date)] = [:]
        for conn in computedConnections {
            newSnapshots[conn.id] = (conn.upload, conn.download, now)
        }
        previousSnapshots = newSnapshots

        // 2. Grouping Logic
        return (computedConnections, group(connections: computedConnections, sessions: appSessions, mode: groupingMode))
    }

    func regroup(connections: [Connection], sessions: [AppSession], mode: GroupingMode) -> [ActivityNode] {
        return group(connections: connections, sessions: sessions, mode: mode)
    }

    private func group(connections: [Connection], sessions: [AppSession], mode: GroupingMode) -> [ActivityNode] {
        switch mode {
        case .app:
            let byID = Dictionary(uniqueKeysWithValues: connections.map { ($0.id, $0) })
            return sessions.map { session in
                var updated = session
                updated.activeConnections = session.activeConnections.map { byID[$0.id] ?? $0 }
                return ActivityNode.app(updated)
            }

        case .proxy:
            let groups = Dictionary(grouping: connections) { conn -> String in
                conn.chains.first ?? "DIRECT"
            }
            return groups.map { id, conns in
                ActivityNode.group(ActivityGroup(id: id, title: id, icon: "network", connections: conns))
            }

        case .host:
            let groups = Dictionary(grouping: connections) { conn -> String in
                conn.metadata.host.isEmpty ? conn.metadata.destinationIP : conn.metadata.host
            }
            return groups.map { id, conns in
                ActivityNode.group(ActivityGroup(id: id, title: id, icon: "globe", connections: conns))
            }

        case .rule:
            let groups = Dictionary(grouping: connections) { conn -> String in
                conn.rule.isEmpty ? "Unmatched" : conn.rule
            }
            return groups.map { id, conns in
                ActivityNode.group(ActivityGroup(id: id, title: id, icon: "list.bullet.rectangle", connections: conns))
            }
        }
    }
}
