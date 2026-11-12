import Foundation
import Yams

/// Read-only metadata. Never retains credentials, opens sockets or starts a core.
public struct SubscriptionSnapshot: Sendable {
    public struct Node: Sendable {
        public let name: String
        public let type: String
    }
    public struct Group: Sendable {
        public let name: String
        public let type: String
        public let members: [String]
    }
    public let nodes: [Node]
    public let groups: [Group]
    public let providerCount: Int

    public static func parse(_ text: String) throws -> Self {
        guard let root = try Yams.load(yaml: text) as? [String: Any] else {
            throw ParseError.invalidDocument
        }
        var names = Set<String>()
        let nodes = (root["proxies"] as? [[String: Any]] ?? []).compactMap { item -> Node? in
            guard let name = item["name"] as? String, !name.isEmpty,
                  let type = item["type"] as? String, names.insert(name).inserted else { return nil }
            return Node(name: name, type: type)
        }
        var groupNames = Set<String>()
        var groups = (root["proxy-groups"] as? [[String: Any]] ?? []).compactMap { item -> Group? in
            guard let name = item["name"] as? String, !name.isEmpty,
                  let type = item["type"] as? String, groupNames.insert(name).inserted else { return nil }
            var members = Set<String>()
            return Group(name: name, type: type, members: (item["proxies"] as? [String] ?? []).filter { members.insert($0).inserted })
        }
        // Bare proxy lists are valid subscriptions too. Give them a browseable group.
        if groups.isEmpty, !nodes.isEmpty {
            groups = [Group(name: "Subscription nodes", type: "select", members: nodes.map(\.name))]
        }
        return Self(nodes: nodes, groups: groups, providerCount: (root["proxy-providers"] as? [String: Any])?.count ?? 0)
    }

    public enum ParseError: Error { case invalidDocument }
}
