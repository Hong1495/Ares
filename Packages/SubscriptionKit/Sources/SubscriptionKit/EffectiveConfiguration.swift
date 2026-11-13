import Foundation
import Yams

/// Builds a separate runtime document. Source YAML is never modified. No I/O or core access.
public enum EffectiveConfiguration {
    public struct LocalProxy: Sendable {
        public let name: String
        public let port: Int
        public init(name: String, port: Int) { self.name = name; self.port = port }
    }

    public enum BuildError: LocalizedError {
        case invalidDocument, invalidSection, duplicateKey, proxyNameConflict
        // Parser diagnostics may contain credentials. Never propagate them to logs/UI.
        public var errorDescription: String? {
            switch self {
            case .invalidDocument: return "Configuration must be one valid YAML mapping."
            case .invalidSection: return "A configuration section has an unexpected type."
            case .duplicateKey: return "Configuration contains duplicate YAML keys."
            case .proxyNameConflict: return "The subscription uses a proxy name reserved for local interception."
            }
        }
    }

    public static func build(source: String, defaults: String, overrides: [[String]],
                             rules: [String] = [], localProxy: LocalProxy? = nil,
                             fingerprint: String? = nil) throws -> String {
        do {
            var result = try parse(source)
            let base = try parse(defaults)
            // Root defaults only: an existing DNS/sniffer section is an intentional configuration,
            // not an invitation to add fake-ip/fallback policies that the subscription omitted.
            for (key, value) in base.mapping! where result[key] == nil { result[key] = value }
            // TUN needs routing defaults when only enable was supplied. Lists stay atomic.
            for section in ["tun", "profile"] {
                if let values = base[section]?.mapping {
                    guard result[section]?.mapping != nil else { throw BuildError.invalidSection }
                    for (key, value) in values where result[section]?[key] == nil {
                        result[section]?[key] = value
                    }
                }
            }
            for path in overrides {
                try assign(path[...], from: base, to: &result)
            }
            if let fingerprint, fingerprint != "none" {
                let targets: Set<String> = ["ss", "vmess", "vless", "trojan", "hysteria", "hysteria2", "tuic"]
                if let existing = result["proxies"] {
                    guard let nodes = existing.sequence else { throw BuildError.invalidSection }
                    result["proxies"] = .sequence(.init(try nodes.map { node in
                        guard node.mapping != nil else { throw BuildError.invalidSection }
                        var node = node
                        if let type = node["type"]?.string, targets.contains(type), node["client-fingerprint"] == nil {
                            node["client-fingerprint"] = Node(fingerprint, Tag(.str))
                        }
                        return node
                    }))
                }
            }
            if let proxy = localProxy {
                let nodes = try sequence(result["proxies"])
                let groups = try sequence(result["proxy-groups"])
                let providers = result["proxy-providers"]?.mapping
                guard !(nodes + groups).contains(where: { $0["name"]?.string == proxy.name }),
                      providers?[Node(proxy.name)] == nil else { throw BuildError.proxyNameConflict }
                let port = Node(String(proxy.port), Tag(.int))
                let local: Node = ["name": Node(proxy.name, Tag(.str)), "type": "http", "server": "127.0.0.1", "port": port]
                result["proxies"] = .sequence(.init([local] + nodes))
            }
            if !rules.isEmpty {
                let existing = try sequence(result["rules"])
                guard existing.allSatisfy({ $0.scalar != nil }) else { throw BuildError.invalidSection }
                result["rules"] = .sequence(.init(rules.map { Node($0, Tag(.str)) } + existing))
            }
            return try Yams.serialize(node: result, allowUnicode: true)
        } catch let error as BuildError {
            throw error
        } catch {
            throw BuildError.invalidDocument
        }
    }

    public struct Field: Sendable, Equatable {
        public let value: String
        public let source: String
        public let scalar: String?
    }

    /// Read-only projection of the same merger used to build the runtime document.
    /// Only requested settings are returned; never export the full subscription to the UI.
    public static func inheritedFields(source: String, defaults: String,
                                       paths: [String: [String]]) throws -> [String: Field] {
        do {
            let original = try parse(source)
            let merged = try parse(build(source: source, defaults: defaults, overrides: []))
            return try paths.mapValues { path in
                let node = path.reduce(Optional(merged)) { $0?[$1] }
                let inherited = path.reduce(Optional(original)) { $0?[$1] } != nil
                let value: String
                if let items = node?.sequence {
                    value = try items.map { item in
                        if let scalar = item.scalar { return scalar.string }
                        return try Yams.serialize(node: item, allowUnicode: true).trimmingCharacters(in: .whitespacesAndNewlines)
                    }.joined(separator: ", ")
                } else if let node, node.mapping != nil {
                    value = try Yams.serialize(node: node, allowUnicode: true).trimmingCharacters(in: .whitespacesAndNewlines)
                } else { value = node?.string ?? "Core default" }
                return Field(value: value, source: inherited ? "Subscription" : (node == nil ? "Core default" : "Ares default"),
                             scalar: node?.scalar != nil ? node?.string : nil)
            }
        } catch let error as BuildError { throw error }
        catch { throw BuildError.invalidDocument }
    }

    private static func sequence(_ node: Node?) throws -> [Node] {
        guard let node else { return [] }
        guard let values = node.sequence else { throw BuildError.invalidSection }
        return Array(values)
    }

    private static func parse(_ text: String) throws -> Node {
        guard let root = try Yams.compose(yaml: text), root.mapping != nil else { throw BuildError.invalidDocument }
        return try resolved(root)
    }

    /// Expand YAML aliases/merge keys before overlays; preserve scalar tags (e.g. quoted passwords).
    /// Explicit duplicate keys are rejected rather than silently selecting a different value.
    private static func resolved(_ node: Node) throws -> Node {
        if let mapping = node.mapping {
            var explicit = Set<String>()
            var inherited: Node = [:]
            var own: [(Node, Node)] = []
            for (key, value) in mapping {
                guard let name = key.string, explicit.insert(name).inserted else { throw BuildError.duplicateKey }
                if key.tag == Tag(.merge) {
                    let sources: [Node]
                    if value.mapping != nil { sources = [value] }
                    else if let sequence = value.sequence { sources = Array(sequence) }
                    else { throw BuildError.invalidSection }
                    // YAML merge sequences give earlier entries precedence.
                    for source in sources {
                        guard let fields = try resolved(source).mapping else { throw BuildError.invalidSection }
                        for (k, v) in fields where inherited[k] == nil { inherited[k] = v }
                    }
                } else {
                    own.append((key, try resolved(value)))
                }
            }
            for (key, value) in own { inherited[key] = value }
            return inherited
        }
        if let sequence = node.sequence { return .sequence(.init(try sequence.map(resolved))) }
        return node
    }

    private static func assign(_ path: ArraySlice<String>, from base: Node, to result: inout Node) throws {
        guard let key = path.first else { return }
        guard result.mapping != nil else { throw BuildError.invalidSection }
        if path.count == 1 {
            // Missing local value (e.g. cleared TUN device) deliberately removes the inherited key.
            var mapping = result.mapping!
            mapping[key] = base[key]
            result = .mapping(mapping)
        } else {
            guard let next = base[key], next.mapping != nil else { throw BuildError.invalidSection }
            var child = result[key] ?? [:]
            try assign(path.dropFirst(), from: next, to: &child)
            result[key] = child
        }
    }
}
