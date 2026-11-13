import Foundation
import Yams

/// Advanced DNS overlays. Basic nameserver/IPv6 and runtime enable remain owned by existing settings.
public enum DNSConfiguration {
    public struct Field: Identifiable, Sendable {
        public let key: String
        public let title: String
        public let kind: String
        public let example: String
        public var id: String { key }
    }
    public static let fields: [Field] = [
        .init(key: "nameserver-policy", title: "Domain Policies", kind: "mapping", example: "'+.internal.test': [192.0.2.53]"),
        .init(key: "proxy-server-nameserver", title: "Proxy Host Resolvers", kind: "list", example: "- 1.1.1.1"),
        .init(key: "proxy-server-nameserver-policy", title: "Proxy Host Policies", kind: "mapping", example: "'+.node.test': [1.1.1.1]"),
        .init(key: "direct-nameserver", title: "Direct Resolvers", kind: "list", example: "- 223.5.5.5"),
        .init(key: "direct-nameserver-follow-policy", title: "Direct Follows Policy", kind: "bool", example: "false"),
        .init(key: "default-nameserver", title: "Bootstrap Resolvers", kind: "list", example: "- 1.1.1.1"),
        .init(key: "fallback", title: "Fallback Resolvers", kind: "list", example: "- https://dns.google/dns-query"),
        .init(key: "fallback-filter", title: "Fallback Filter", kind: "mapping", example: "geoip: false\nipcidr: [240.0.0.0/4]"),
        .init(key: "enhanced-mode", title: "DNS Mode", kind: "mode", example: "fake-ip"),
        .init(key: "fake-ip-filter", title: "Fake IP Filter", kind: "list", example: "- '+.internal.test'"),
        .init(key: "fake-ip-filter-mode", title: "Fake IP Filter Mode", kind: "filterMode", example: "blacklist"),
        .init(key: "respect-rules", title: "Resolver Routing", kind: "bool", example: "false"),
        .init(key: "use-hosts", title: "Use Configured Hosts", kind: "bool", example: "true"),
        .init(key: "use-system-hosts", title: "Use System Hosts", kind: "bool", example: "true"),
        .init(key: "hosts", title: "Hosts", kind: "mapping", example: "internal.test: 192.0.2.10")
    ]
    public static func decode(_ text: String) throws -> [String: String] {
        do { return try JSONDecoder().decode([String: String].self, from: Data(text.utf8)) }
        catch { throw EffectiveConfiguration.BuildError.invalidDocument }
    }
    public static func encode(_ values: [String: String]) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(values), as: UTF8.self)
    }
    public static func read(_ source: String) throws -> [String: String] {
        let root = try parse(source)
        var values: [String: String] = [:]
        for field in fields {
            if let node = field.key == "hosts" ? root["hosts"] : root["dns"]?[field.key] {
                values[field.key] = try Yams.serialize(node: node, allowUnicode: true).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return values
    }
    public static func validate(key: String, value: String) throws {
        _ = try valueNode(key: key, value: value)
    }
    public static func apply(source: String, overrides: String) throws -> String {
        let edits = try decode(overrides)
        if edits.isEmpty { return source }
        var root = try parse(source)
        for (key, value) in edits {
            let node = try valueNode(key: key, value: value)
            if key == "hosts" { root["hosts"] = node }
            else {
                var dns = root["dns"] ?? [:]
                guard dns.mapping != nil else { throw EffectiveConfiguration.BuildError.invalidSection }
                dns[key] = node; root["dns"] = dns
            }
        }
        return try Yams.serialize(node: root, allowUnicode: true)
    }
    private static func valueNode(key: String, value: String) throws -> Node {
        guard let field = fields.first(where: { $0.key == key }), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EffectiveConfiguration.BuildError.invalidSection
        }
        // Wrapping permits arbitrary YAML values while reusing duplicate-key/alias validation.
        let wrapped = "value:\n" + value.components(separatedBy: .newlines).map { "  " + $0 }.joined(separator: "\n")
        guard let node = try parse(wrapped)["value"] else { throw EffectiveConfiguration.BuildError.invalidSection }
        switch field.kind {
        case "mapping": guard node.mapping != nil else { throw EffectiveConfiguration.BuildError.invalidSection }
        case "list": guard let list = node.sequence, list.allSatisfy({ $0.tag == Tag(.str) }) else { throw EffectiveConfiguration.BuildError.invalidSection }
        case "bool": guard node.tag == Tag(.bool), node.bool != nil else { throw EffectiveConfiguration.BuildError.invalidSection }
        case "mode": guard ["fake-ip", "redir-host"].contains(node.string ?? "") else { throw EffectiveConfiguration.BuildError.invalidSection }
        case "filterMode": guard ["blacklist", "whitelist", "rule"].contains(node.string ?? "") else { throw EffectiveConfiguration.BuildError.invalidSection }
        default: throw EffectiveConfiguration.BuildError.invalidSection
        }
        return node
    }
    private static func parse(_ text: String) throws -> Node {
        let normalized = try EffectiveConfiguration.build(source: text, defaults: "{}", overrides: [])
        guard let root = try Yams.compose(yaml: normalized) else { throw EffectiveConfiguration.BuildError.invalidDocument }
        return root
    }
}
