import Foundation

/// Profile-scoped choices survive stopped cores and normal/TUN restarts.
nonisolated struct NodeSelectionPlan: Codable {
    private var profiles: [String: [String: String]] = [:]

    func choices(for profile: UUID) -> [String: String] { profiles[profile.uuidString] ?? [:] }

    mutating func select(profile: UUID, group: String, node: String) {
        profiles[profile.uuidString, default: [:]][group] = node
    }

    mutating func remove(profile: UUID) { profiles.removeValue(forKey: profile.uuidString) }

    /// Missing nodes/groups from an updated subscription are ignored. Selection
    /// failures for still-valid choices must fail activation before traffic is routed.
    static func restore(_ choices: [String: String], groups: [ProxyGroup], select: (String, String) async throws -> Void) async throws {
        for group in groups where group.type == "Selector" {
            guard let node = choices[group.name], group.all.contains(node), group.now != node else { continue }
            try await select(group.name, node)
        }
    }
}
