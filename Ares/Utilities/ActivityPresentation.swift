import Foundation

nonisolated enum ActivityPresentation {
    static func matches(_ connection: Connection, query: String) -> Bool {
        [connection.processName, connection.metadata.processPath ?? "", connection.metadata.host,
         connection.metadata.destinationIP, connection.metadata.sourceIP, connection.rule,
         connection.rulePayload, connection.chainsString, connection.typeString]
            .contains { $0.localizedCaseInsensitiveContains(query) }
    }

    static func filter(_ nodes: [ActivityNode], query: String) -> [ActivityNode] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nodes }
        return nodes.compactMap { node in
            if node.title.localizedCaseInsensitiveContains(query) { return node }
            switch node {
            case .connection(let connection): return matches(connection, query: query) ? node : nil
            case .app(var session):
                session.activeConnections = session.activeConnections.filter { matches($0, query: query) }
                session.activeConnectionCount = session.activeConnections.count
                return session.activeConnections.isEmpty ? nil : .app(session)
            case .group(let group):
                let children = group.connections.filter { matches($0, query: query) }
                return children.isEmpty ? nil : .group(ActivityGroup(id: group.id, title: group.title, icon: group.icon, connections: children))
            }
        }
    }

    static func sorted(_ nodes: [ActivityNode], using order: [KeyPathComparator<ActivityNode>]) -> [ActivityNode] {
        nodes.map { node in
            switch node {
            case .app(var session):
                session.activeConnections = sortedConnections(session.activeConnections, using: order)
                return .app(session)
            case .group(let group):
                return .group(ActivityGroup(id: group.id, title: group.title, icon: group.icon,
                                            connections: sortedConnections(group.connections, using: order)))
            case .connection: return node
            }
        }.sorted(using: order)
    }

    private static func sortedConnections(_ connections: [Connection], using order: [KeyPathComparator<ActivityNode>]) -> [Connection] {
        connections.map(ActivityNode.connection).sorted(using: order).compactMap {
            if case .connection(let connection) = $0 { return connection }
            return nil
        }
    }

    static func csv(_ connections: [Connection]) -> String {
        func field(_ value: String) -> String {
            // Keep spreadsheet applications from interpreting text as formulas.
            let safe = ["=", "+", "-", "@", "\t", "\r"].contains(where: { value.hasPrefix($0) }) ? "'" + value : value
            return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        var lines = ["Time,ID,Process,Type,Host,RemoteIP,RemotePort,Upload,Download,Duration,Rule,Chains"]
        for conn in connections {
            lines.append([conn.start.ISO8601Format(), conn.id, conn.processName, conn.typeString,
                          conn.metadata.host, conn.metadata.destinationIP, conn.metadata.destinationPort,
                          String(conn.upload), String(conn.download), String(max(0, conn.duration)), conn.rule,
                          conn.chains.joined(separator: " -> ")].map(field).joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }
}
