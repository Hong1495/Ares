import Foundation
import Yams

/// Human-editable YAML projection of the private override encodings. No live preferences are written.
public enum SceneOverrideDocument {
    public enum Section: String, CaseIterable { case dns, policy, routing }

    public static func render(_ stored: String, section: Section) throws -> String {
        var root: Node = [:]
        switch section {
        case .dns:
            for (key, value) in try DNSConfiguration.decode(stored) { root[key] = try valueNode(value) }
        case .policy:
            for (group, fields) in try PolicyConfiguration.decodeOverrides(stored) {
                var entry: Node = [:]
                for (key, value) in fields { entry[key] = Node(value, Tag(.str), .doubleQuoted) }
                root[group] = entry
            }
        case .routing:
            let edits = try EgressConfiguration.decode(stored)
            var nodes: Node = [:]
            for (name, fields) in edits.nodes {
                var entry: Node = [:]
                for (key, value) in fields { entry[key] = Node(value, Tag(.str), .doubleQuoted) }
                nodes[name] = entry
            }
            root["nodes"] = nodes
            if let value = edits.interface { root["interface"] = Node(value, Tag(.str), .doubleQuoted) }
            if let value = edits.listeners { root["listeners"] = try valueNode(value) }
            if let value = edits.tunnels { root["tunnels"] = try valueNode(value) }
        }
        return try yaml(root)
    }

    public static func encode(_ document: String, section: Section) throws -> String {
        // Reuse strict duplicate-key, document-count and alias validation.
        let normalized = try EffectiveConfiguration.build(source: document, defaults: "{}", overrides: [])
        guard let root = try Yams.compose(yaml: normalized), let mapping = root.mapping else { throw EffectiveConfiguration.BuildError.invalidDocument }
        switch section {
        case .dns:
            var fields: [String: String] = [:]
            for (key, value) in mapping {
                guard let key = key.string else { throw EffectiveConfiguration.BuildError.invalidSection }
                let text = try yaml(value)
                try DNSConfiguration.validate(key: key, value: text)
                fields[key] = text
            }
            return try DNSConfiguration.encode(fields)
        case .policy:
            var groups: [String: [String: String]] = [:]
            for (key, value) in mapping {
                guard let name = key.string, !name.isEmpty else { throw EffectiveConfiguration.BuildError.invalidSection }
                let fields = try scalars(value)
                // Parameter semantics are checked against the actual group type on apply.
                guard Set(fields.keys).isSubset(of: Set(PolicyConfiguration.fields + PolicyConfiguration.structuralFields)) else { throw EffectiveConfiguration.BuildError.invalidSection }
                groups[name] = fields
            }
            return try PolicyConfiguration.encodeOverrides(groups)
        case .routing:
            guard mapping.allSatisfy({ ["nodes", "interface", "listeners", "tunnels"].contains($0.key.string ?? "") }) else { throw EgressConfiguration.ValidationError.invalid }
            var edits = EgressConfiguration.Overrides()
            if let node = root["nodes"] {
                guard let nodes = node.mapping else { throw EgressConfiguration.ValidationError.invalid }
                for (key, value) in nodes {
                    guard let name = key.string, !name.isEmpty else { throw EgressConfiguration.ValidationError.invalid }
                    let fields = try scalars(value)
                    guard Set(fields.keys).isSubset(of: ["dialer-proxy", "interface-name"]) else { throw EgressConfiguration.ValidationError.invalid }
                    edits.nodes[name] = fields
                }
            }
            if let node = root["interface"] {
                guard node.tag == Tag(.str), let value = node.string else { throw EgressConfiguration.ValidationError.invalid }
                edits.interface = value
            }
            if let node = root["listeners"] {
                guard node.sequence != nil else { throw EgressConfiguration.ValidationError.invalid }
                edits.listeners = try yaml(node)
            }
            if let node = root["tunnels"] {
                guard node.sequence != nil else { throw EgressConfiguration.ValidationError.invalid }
                edits.tunnels = try yaml(node)
            }
            return try EgressConfiguration.encode(edits)
        }
    }
    private static func scalars(_ node: Node) throws -> [String: String] {
        guard let fields = node.mapping else { throw EffectiveConfiguration.BuildError.invalidSection }
        var result: [String: String] = [:]
        for (key, value) in fields {
            guard let name = key.string, let value = value.scalar?.string, !name.isEmpty else { throw EffectiveConfiguration.BuildError.invalidSection }
            result[name] = value
        }
        return result
    }
    private static func valueNode(_ text: String) throws -> Node {
        let wrapped = "value:\n" + text.components(separatedBy: .newlines).map { "  " + $0 }.joined(separator: "\n")
        let normalized = try EffectiveConfiguration.build(source: wrapped, defaults: "{}", overrides: [])
        guard let value = try Yams.compose(yaml: normalized)?["value"] else { throw EffectiveConfiguration.BuildError.invalidDocument }
        return value
    }
    private static func yaml(_ node: Node) throws -> String { try Yams.serialize(node: node, allowUnicode: true) }
}
