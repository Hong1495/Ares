import Foundation

/// Profile-scoped choices survive stopped cores and normal/TUN restarts.
nonisolated struct NodeSelectionPlan: Codable {
    private var profiles: [String: [String: String]] = [:]

    func choices(for profile: UUID) -> [String: String] { profiles[profile.uuidString] ?? [:] }

    mutating func select(profile: UUID, group: String, node: String) {
        profiles[profile.uuidString, default: [:]][group] = node
    }

    mutating func clear(profile: UUID, group: String) {
        profiles[profile.uuidString]?.removeValue(forKey: group)
    }

    mutating func replace(profile: UUID, choices: [String: String]) { profiles[profile.uuidString] = choices }

    mutating func remove(profile: UUID) { profiles.removeValue(forKey: profile.uuidString) }

    static func validate(_ choices: [String: String], groups: [ProxyGroup]) throws {
        for (name, node) in choices {
            guard let group = groups.first(where: { $0.name == name }), group.supportsManualSelection,
                  group.all.contains(node) else { throw SelectionError.unavailable }
        }
    }
    enum SelectionError: Error { case unavailable }

    /// Missing nodes/groups from an updated subscription are ignored. Selection
    /// failures for still-valid choices must fail activation before traffic is routed.
    static func restore(_ choices: [String: String], groups: [ProxyGroup], reset: (String) async throws -> Void = { _ in }, select: (String, String) async throws -> Void) async throws {
        for group in groups where group.supportsManualSelection {
            if group.supportsAutomaticSelection,
               choices[group.name].map({ group.all.contains($0) }) != true {
                if group.manualSelection != nil { try await reset(group.name) }
                continue
            }
            guard let node = choices[group.name], group.all.contains(node), !group.confirmsSelection(node) else { continue }
            try await select(group.name, node)
        }
    }
}
