import Foundation
import Yams

/// Lossless value-level form projections: unsupported values remain available in Source.
public enum NetworkFormDocument {
    public struct Entry: Identifiable, Equatable, Sendable {
        public var key: String
        public var values: [String]
        public var isList: Bool
        public var id: String { key }
        public init(key: String, values: [String], isList: Bool = true) { self.key = key; self.values = values; self.isList = isList }
    }
    public static func strings(_ text: String) throws -> [String] {
        let node = try value(text)
        guard let sequence = node.sequence, sequence.allSatisfy({ $0.tag == Tag(.str) }) else { throw Failure.unsupported }
        return sequence.compactMap(\.string)
    }
    public static func strings(_ values: [String]) throws -> String {
        try yaml(.sequence(.init(values.map { Node($0, Tag(.str), .doubleQuoted) })))
    }
    public static func entries(_ text: String) throws -> [Entry] {
        guard let mapping = try value(text).mapping else { throw Failure.unsupported }
        return try mapping.map { key, node in
            guard key.tag == Tag(.str), let key = key.string else { throw Failure.unsupported }
            if node.tag == Tag(.str), let scalar = node.string { return Entry(key: key, values: [scalar], isList: false) }
            guard let list = node.sequence, list.allSatisfy({ $0.tag == Tag(.str) }) else { throw Failure.unsupported }
            return Entry(key: key, values: list.compactMap(\.string))
        }
    }
    public static func entries(_ rows: [Entry]) throws -> String {
        guard Set(rows.map(\.key)).count == rows.count, rows.allSatisfy({ !$0.key.isEmpty && ($0.isList || $0.values.count == 1) }) else { throw Failure.invalid }
        return try yaml(.mapping(.init(try rows.map { row in
            let node = row.isList ? try value(strings(row.values)) : Node(row.values[0], Tag(.str), .doubleQuoted)
            return (Node(row.key, Tag(.str), .doubleQuoted), node)
        })))
    }
    public struct Record: Identifiable, Sendable {
        public let id: Int
        public let title: String
        public let fields: [String: String]?
    }
    public enum Section: String, Sendable { case listeners, tunnels }
    public static func records(_ text: String, section: Section) throws -> [Record] {
        guard let sequence = try value(text).sequence else { throw Failure.unsupported }
        return sequence.enumerated().map { index, node in
            let title = node["name"]?.string ?? node["address"]?.string ?? "Entry \(index + 1)"
            var fields: [String: String] = [:]
            let keys = section == .listeners ? ["name", "type", "listen", "port", "proxy", "udp"] : ["address", "target", "proxy"]
            guard node.mapping != nil else { return Record(id: index, title: title, fields: nil) }
            for key in keys {
                if let v = node[key] {
                    guard let scalar = v.scalar?.string else { return Record(id: index, title: title, fields: nil) }
                    fields[key] = scalar
                }
            }
            if section == .listeners {
                guard ["http", "socks", "mixed"].contains(fields["type"] ?? ""), let port = Int(fields["port"] ?? ""), (1...65535).contains(port) else { return Record(id: index, title: title, fields: nil) }
            } else {
                guard let networks = node["network"]?.sequence, networks.allSatisfy({ ["tcp", "udp"].contains($0.string ?? "") }) else { return Record(id: index, title: title, fields: nil) }
                fields["network"] = networks.compactMap(\.string).joined(separator: ",")
            }
            return Record(id: index, title: title, fields: fields)
        }
    }
    /// Patches only form-owned fields in one row. Unknown TLS, authentication and future fields survive.
    public static func saveRecord(_ text: String, section: Section, index: Int?, fields: [String: String]) throws -> String {
        guard let seq = try value(text).sequence else { throw Failure.unsupported }
        var rows = Array(seq)
        if let index { guard rows.indices.contains(index), rows[index].mapping != nil else { throw Failure.invalid } }
        var node: Node = index.map { rows[$0] } ?? [:]
        let allowed = section == .listeners ? Set(["name", "type", "listen", "port", "proxy", "udp"]) : Set(["address", "target", "proxy", "network"])
        guard Set(fields.keys).isSubset(of: allowed) else { throw Failure.invalid }
        for (key, text) in fields {
            switch key {
            case "port":
                guard let port = Int(text), (1...65535).contains(port) else { throw Failure.invalid }
                node[key] = Node(String(port), Tag(.int))
            case "udp":
                guard ["true", "false"].contains(text) else { throw Failure.invalid }
                node[key] = Node(text, Tag(.bool))
            case "network":
                let networks = text.split(separator: ",").map(String.init)
                guard !networks.isEmpty, Set(networks).count == networks.count, networks.allSatisfy({ ["tcp", "udp"].contains($0) }) else { throw Failure.invalid }
                node[key] = try value(strings(networks))
            default: node[key] = Node(text, Tag(.str), .doubleQuoted)
            }
        }
        if section == .listeners {
            guard let name = node["name"]?.string, !name.isEmpty, ["http", "socks", "mixed"].contains(node["type"]?.string ?? ""),
                  EgressConfiguration.isIP(node["listen"]?.string ?? ""), node["port"]?.int != nil else { throw Failure.invalid }
            guard !rows.enumerated().contains(where: { $0.offset != index && $0.element["name"]?.string == name }) else { throw Failure.invalid }
        } else {
            guard !(node["address"]?.string ?? "").isEmpty, !(node["target"]?.string ?? "").isEmpty else { throw Failure.invalid }
        }
        if let index { rows[index] = node } else { rows.append(node) }
        return try yaml(.sequence(.init(rows)))
    }
    public static func removeRecord(_ text: String, index: Int) throws -> String {
        guard let sequence = try value(text).sequence, sequence.indices.contains(index) else { throw Failure.invalid }
        var rows = Array(sequence); rows.remove(at: index)
        return try yaml(.sequence(.init(rows)))
    }
    public enum Failure: LocalizedError {
        case unsupported, invalid
        public var errorDescription: String? { self == .unsupported ? "This value contains advanced syntax. Use Source to preserve it." : "Check names, values, addresses and ports. Duplicate entries are not allowed." }
    }
    private static func value(_ text: String) throws -> Node {
        let source = "value:\n" + text.components(separatedBy: .newlines).map { "  " + $0 }.joined(separator: "\n")
        guard let node = try Yams.compose(yaml: EffectiveConfiguration.build(source: source, defaults: "{}", overrides: []))?["value"] else { throw Failure.invalid }
        return node
    }
    private static func yaml(_ node: Node) throws -> String { try Yams.serialize(node: node, allowUnicode: true) }
}
