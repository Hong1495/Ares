import Foundation

/// Allowlisted runtime resource metadata; proxy credentials and subscription URLs are never retained.
nonisolated struct ProxyResource: Decodable, Identifiable, Sendable {
    struct Member: Decodable, Identifiable, Sendable {
        struct Measurement: Decodable, Sendable { let time: String; let delay: Int }
        let name: String
        let type: String
        let alive: Bool?
        let history: [Measurement]?
        var id: String { name }
        var latest: Measurement? { history?.last }
    }
    let name: String
    let vehicleType: String
    let proxies: [Member]
    let updatedAt: String?
    var id: String { name }
    var canUpdate: Bool { ["HTTP", "File"].contains(vehicleType) }
    var updatedDate: Date? { Self.date(updatedAt) }
    static func date(_ value: String?) -> Date? {
        guard let value, !value.hasPrefix("0001-") else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
    static func decode(_ data: Data) throws -> [ProxyResource] {
        struct Response: Decodable { let providers: [String: ProxyResource] }
        let resources = try JSONDecoder().decode(Response.self, from: data).providers
        guard resources.allSatisfy({ key, resource in
            key == resource.name && Set(resource.proxies.map(\.name)).count == resource.proxies.count &&
                resource.proxies.allSatisfy { !$0.name.isEmpty && ($0.latest?.delay ?? 0) >= 0 }
        }) else { throw URLError(.cannotParseResponse) }
        return resources.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// Runtime graph: an edge is group membership, never a physical route or a load-balanced connection's exit.
nonisolated enum PolicyGraph {
    struct Edge: Identifiable, Sendable {
        let parent: String
        let member: String
        let kind: String
        let active: Bool
        var id: String { "\(parent.utf8.count):\(parent)\(member)" }
    }
    struct Snapshot: Sendable {
        let edges: [Edge]
        let issues: [String]
    }
    static func inspect(groups: [ProxyGroup], nodes: [String: ProxyNode]) -> Snapshot {
        let byName = Dictionary(groups.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        var edges: [Edge] = [], issues: [String] = []
        let builtIns: Set<String> = ["DIRECT", "REJECT", "REJECT-DROP", "PASS", "COMPATIBLE", "PASS-RULE"]
        for group in groups {
            for member in group.all {
                let kind = byName[member] != nil ? "Group" : (builtIns.contains(member) ? "Built-in" : nodes[member]?.type ?? "Unavailable")
                edges.append(Edge(parent: group.name, member: member, kind: kind,
                    active: group.type != "LoadBalance" && group.now == member))
                if kind == "Unavailable" { issues.append("\(group.name) → \(member): member unavailable in this snapshot.") }
            }
        }
        // Iterative DFS covers every edge without recursion or a node-count cap.
        var done = Set<String>(), visiting = Set<String>()
        for name in byName.keys.sorted() where !done.contains(name) {
            var stack: [(String, Int)] = [(name, 0)]
            visiting.insert(name)
            while let (current, offset) = stack.last {
                let members = byName[current]?.all ?? []
                if offset >= members.count {
                    visiting.remove(current); done.insert(current); stack.removeLast(); continue
                }
                stack[stack.count - 1].1 += 1
                let next = members[offset]
                guard byName[next] != nil else { continue }
                if visiting.contains(next) { issues.append("Cycle: \(current) → \(next)"); continue }
                if !done.contains(next) { visiting.insert(next); stack.append((next, 0)) }
            }
        }
        return Snapshot(edges: edges, issues: issues)
    }
}
