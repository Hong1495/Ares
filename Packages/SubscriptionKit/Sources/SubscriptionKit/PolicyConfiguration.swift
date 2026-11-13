import Foundation
import Yams

/// Existing-group parameter overrides, scoped by the caller to one subscription. Unknown fields survive.
public enum PolicyConfiguration {
    public struct Group: Identifiable, Sendable {
        public let name: String
        public let type: String
        public let members: [String]
        public let providers: [String]
        public let fields: [String: String]
        public var id: String { name }
    }
    public static let fields = ["interval", "timeout", "tolerance", "lazy", "filter", "exclude-filter", "strategy"]
    public static func editableFields(type: String) -> [String] {
        let common = ["filter", "exclude-filter"]
        switch type {
        case "select": return common
        case "url-test": return ["interval", "timeout", "tolerance", "lazy"] + common
        case "fallback": return ["interval", "timeout", "lazy"] + common
        case "load-balance": return ["interval", "timeout", "lazy", "strategy"] + common
        default: return []
        }
    }
    public static func read(_ text: String) throws -> [Group] {
        let root = try parse(text)
        guard let node = root["proxy-groups"] else { return [] }
        guard let groups = node.sequence else { throw EffectiveConfiguration.BuildError.invalidSection }
        var seen = Set<String>()
        return try groups.map { node in
            guard let name = node["name"]?.string, seen.insert(name).inserted, let type = node["type"]?.string else {
                throw EffectiveConfiguration.BuildError.invalidSection
            }
            var values: [String: String] = [:]
            for field in fields { if let value = node[field]?.scalar?.string { values[field] = value } }
            return Group(name: name, type: type, members: try strings(node["proxies"]), providers: try strings(node["use"]), fields: values)
        }
    }
    public static func decodeOverrides(_ json: String) throws -> [String: [String: String]] {
        guard let data = json.data(using: .utf8) else { throw EffectiveConfiguration.BuildError.invalidDocument }
        return try JSONDecoder().decode([String: [String: String]].self, from: data)
    }
    public static func encodeOverrides(_ values: [String: [String: String]]) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(values), as: UTF8.self)
    }
    public static func apply(source: String, overrides: String) throws -> String {
        let edits = try decodeOverrides(overrides)
        if edits.isEmpty { return source }
        var root = try parse(source)
        guard let sequence = root["proxy-groups"]?.sequence,
              Set(edits.keys).isSubset(of: Set(sequence.compactMap { $0["name"]?.string })) else {
            throw EffectiveConfiguration.BuildError.invalidSection
        }
        root["proxy-groups"] = .sequence(.init(try sequence.map { node in
            guard let name = node["name"]?.string, let type = node["type"]?.string else { throw EffectiveConfiguration.BuildError.invalidSection }
            guard let fields = edits[name] else { return node }
            let allowed = Set(editableFields(type: type))
            var result = node
            for (key, value) in fields {
                guard allowed.contains(key) else { throw EffectiveConfiguration.BuildError.invalidSection }
                switch key {
                case "interval", "timeout", "tolerance":
                    guard let number = UInt32(value), (key != "timeout" || number > 0), (key != "tolerance" || number <= UInt16.max) else { throw EffectiveConfiguration.BuildError.invalidSection }
                    result[key] = Node(String(number), Tag(.int))
                case "lazy":
                    guard ["true", "false"].contains(value) else { throw EffectiveConfiguration.BuildError.invalidSection }
                    result[key] = Node(value, Tag(.bool))
                case "strategy":
                    guard ["consistent-hashing", "round-robin", "sticky-sessions"].contains(value) else { throw EffectiveConfiguration.BuildError.invalidSection }
                    result[key] = Node(value, Tag(.str))
                default: result[key] = Node(value, Tag(.str), .doubleQuoted)
                }
            }
            return result
        }))
        return try Yams.serialize(node: root, allowUnicode: true)
    }
    private static func strings(_ node: Node?) throws -> [String] {
        guard let node else { return [] }
        guard let values = node.sequence else { throw EffectiveConfiguration.BuildError.invalidSection }
        return try values.map { guard let text = $0.string else { throw EffectiveConfiguration.BuildError.invalidSection }; return text }
    }
    private static func parse(_ text: String) throws -> Node {
        let normalized = try EffectiveConfiguration.build(source: text, defaults: "{}", overrides: [])
        guard let root = try Yams.compose(yaml: normalized) else { throw EffectiveConfiguration.BuildError.invalidDocument }
        return root
    }
}
