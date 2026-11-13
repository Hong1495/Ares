import Foundation
import Yams

/// Subscription-scoped edits. Credentials remain in the document, never in catalog projections.
public enum ManagedResources {
    public struct Draft: Codable, Equatable, Sendable {
        public var nodes: [String: String] = [:]
        public var providers: [String: String] = [:]
        public var removedNodes: Set<String> = []
        public var removedProviders: Set<String> = []
        public init() {}
    }
    public struct Entry: Identifiable, Sendable {
        public let name: String
        public let type: String
        public let provider: Bool
        public let local: Bool
        public var id: String { (provider ? "provider:" : "node:") + name }
    }
    public enum Failure: LocalizedError {
        case invalid(String)
        public var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
    }
    public static func decode(_ text: String) throws -> Draft { try JSONDecoder().decode(Draft.self, from: Data(text.utf8)) }
    public static func encode(_ draft: Draft) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(draft), as: UTF8.self)
    }
    public static func document(_ text: String) throws -> Node {
        guard let node = try Yams.compose(yaml: EffectiveConfiguration.build(source: text, defaults: "{}", overrides: [])), node.mapping != nil else { throw Failure.invalid("Use a YAML mapping.") }
        return node
    }
    public static func yaml(_ node: Node) throws -> String { try Yams.serialize(node: node, allowUnicode: true) }
    public static func validName(_ name: String) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 160 && !name.contains(where: { $0.isNewline || $0 == "," || $0.isASCII && $0.asciiValue! < 32 }) && !["DIRECT", "REJECT", "GLOBAL", "PASS", "COMPATIBLE", "REJECT-DROP"].contains(name)
    }
    public static func apply(source: String, draft: Draft) throws -> String {
        if draft == Draft() { return source }
        var root = try document(source)
        var nodes = Array(root["proxies"]?.sequence ?? [])
        nodes.removeAll { draft.removedNodes.contains($0["name"]?.string ?? "") }
        for name in draft.nodes.keys.sorted() {
            guard validName(name), !draft.removedNodes.contains(name) else { throw Failure.invalid("Invalid or conflicting node name.") }
            var node = try document(draft.nodes[name]!)
            node["name"] = Node(name, Tag(.str))
            try validateNode(node)
            if let index = nodes.firstIndex(where: { $0["name"]?.string == name }) { nodes[index] = node } else { nodes.append(node) }
        }
        let names = nodes.compactMap { $0["name"]?.string }
        let groups = (root["proxy-groups"]?.sequence ?? []).compactMap { $0["name"]?.string }
        guard names.count == Set(names).count, Set(names).isDisjoint(with: Set(groups)) else { throw Failure.invalid("Node and policy names must be unique.") }
        root["proxies"] = .sequence(.init(nodes))
        var providers = root["proxy-providers"] ?? .mapping([:])
        guard let mapping = providers.mapping else { throw Failure.invalid("Invalid provider document.") }
        providers = .mapping(.init(mapping.filter { !draft.removedProviders.contains($0.key.string ?? "") }.map { ($0.key, $0.value) }))
        for name in draft.providers.keys.sorted() {
            guard validName(name), !draft.removedProviders.contains(name) else { throw Failure.invalid("Invalid or conflicting provider name.") }
            let node = try document(draft.providers[name]!)
            guard ["http", "file", "inline"].contains(node["type"]?.string ?? "") else { throw Failure.invalid("Provider type must be http, file or inline.") }
            if node["type"]?.string == "http" {
                guard let url = node["url"]?.string.flatMap(URL.init(string:)), ["http", "https"].contains(url.scheme), url.host != nil else { throw Failure.invalid("Use an HTTP or HTTPS provider URL.") }
                guard let interval = node["interval"]?.int, interval > 0 else { throw Failure.invalid("Provider update interval must be positive.") }
            }
            if let path = node["path"]?.string {
                guard !path.hasPrefix("/"), !path.split(separator: "/").contains(".."), !path.isEmpty else { throw Failure.invalid("Provider cache paths must stay inside the core directory.") }
            }
            providers[name] = node
        }
        root["proxy-providers"] = providers
        return try yaml(root)
    }
    public static func validateNode(_ node: Node) throws {
        guard let type = node["type"]?.string, !type.isEmpty, let server = node["server"]?.string, !server.isEmpty,
              !server.contains(where: { $0.isWhitespace }), let port = node["port"]?.int, (1...65535).contains(port) else { throw Failure.invalid("A node requires a type, server and valid port.") }
        if ["vless", "vmess"].contains(type) { guard let uuid = node["uuid"]?.string, UUID(uuidString: uuid) != nil else { throw Failure.invalid("Use a valid UUID.") } }
        if ["trojan", "ss"].contains(type) { guard let password = node["password"]?.string, !password.isEmpty else { throw Failure.invalid("This protocol requires a password.") } }
        if type == "ss" { guard let cipher = node["cipher"]?.string, !cipher.isEmpty else { throw Failure.invalid("Shadowsocks requires a cipher.") } }
    }
    public static func entries(source: String, draft: Draft) throws -> [Entry] {
        let root = try document(apply(source: source, draft: draft))
        let nodes = (root["proxies"]?.sequence ?? []).compactMap { node -> Entry? in
            guard let name = node["name"]?.string else { return nil }
            return Entry(name: name, type: node["type"]?.string ?? "—", provider: false, local: draft.nodes[name] != nil)
        }
        let providers = (root["proxy-providers"]?.mapping ?? [:]).compactMap { item -> Entry? in
            guard let name = item.key.string else { return nil }
            return Entry(name: name, type: item.value["type"]?.string ?? "—", provider: true, local: draft.providers[name] != nil)
        }
        return (nodes + providers).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    public static func entry(source: String, draft: Draft, name: String, provider: Bool) throws -> String {
        let root = try document(apply(source: source, draft: draft))
        guard let node = provider ? root["proxy-providers"]?[name] : root["proxies"]?.sequence?.first(where: { $0["name"]?.string == name }) else { throw Failure.invalid("Resource no longer exists.") }
        return try yaml(node)
    }
    /// Reject unknown URI options rather than silently dropping protocol/security settings.
    public static func importLinks(_ text: String) throws -> [String: String] {
        var result: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline).map({ $0.trimmingCharacters(in: .whitespaces) }) where !line.isEmpty {
            guard let url = URLComponents(string: line), let scheme = url.scheme?.lowercased(), ["vless", "trojan", "ss"].contains(scheme),
                  let host = url.host, let port = url.port, (1...65535).contains(port), let user = url.user else { throw Failure.invalid("Use VLESS, Trojan or SIP002 Shadowsocks links. Import other configurations as YAML.") }
            let name = url.fragment.flatMap { $0.isEmpty ? nil : $0 } ?? "\(scheme.uppercased()) · \(host):\(port)"
            guard validName(name), result[name] == nil else { throw Failure.invalid("Duplicate or invalid imported name. Rename the link before importing.") }
            var node: Node = ["name": Node(name, Tag(.str)), "type": Node(scheme, Tag(.str)), "server": Node(host, Tag(.str)), "port": Node(String(port), Tag(.int))]
            var query: [String: String] = [:]
            for item in url.queryItems ?? [] {
                guard query[item.name] == nil else { throw Failure.invalid("Duplicate link parameter.") }
                query[item.name] = item.value ?? ""
            }
            if scheme == "ss" {
                guard query.isEmpty else { throw Failure.invalid("Shadowsocks plugins require YAML import.") }
                let credential: String
                if let password = url.password { credential = user + ":" + password }
                else {
                    var encoded = user.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
                    encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
                    guard let data = Data(base64Encoded: encoded), let decoded = String(data: data, encoding: .utf8) else { throw Failure.invalid("Invalid Shadowsocks credentials.") }; credential = decoded
                }
                let parts = credential.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2 else { throw Failure.invalid("Invalid Shadowsocks credentials.") }
                node["cipher"] = Node(String(parts[0]), Tag(.str)); node["password"] = Node(String(parts[1]), Tag(.str))
            } else {
                let supported: Set<String> = ["security", "encryption", "type", "sni", "peer", "fp", "pbk", "sid", "flow", "path", "host", "serviceName", "alpn", "allowInsecure"]
                guard Set(query.keys).isSubset(of: supported), url.password == nil else { throw Failure.invalid("Unsupported link parameter. Use YAML to preserve all settings.") }
                if let encryption = query["encryption"], encryption != "none" { throw Failure.invalid("Unsupported VLESS encryption.") }
                node[scheme == "vless" ? "uuid" : "password"] = Node(user, Tag(.str))
                let security = query["security"] ?? (scheme == "trojan" ? "tls" : "none")
                guard ["none", "tls", "reality"].contains(security), scheme != "trojan" || security == "tls" else { throw Failure.invalid("Unsupported TLS mode.") }
                if scheme == "vless" { node["tls"] = Node(security == "none" ? "false" : "true", Tag(.bool)) }
                if let sni = query["sni"] ?? query["peer"] { node[scheme == "trojan" ? "sni" : "servername"] = Node(sni, Tag(.str)) }
                if let fp = query["fp"] { node["client-fingerprint"] = Node(fp, Tag(.str)) }
                if let flow = query["flow"] { node["flow"] = Node(flow, Tag(.str)) }
                if let insecure = query["allowInsecure"] {
                    guard ["0", "1", "true", "false"].contains(insecure) else { throw Failure.invalid("Invalid TLS verification option.") }
                    node["skip-cert-verify"] = Node(["1", "true"].contains(insecure) ? "true" : "false", Tag(.bool))
                }
                if let alpn = query["alpn"] { node["alpn"] = .sequence(.init(alpn.split(separator: ",").map { Node(String($0), Tag(.str)) })) }
                if security == "reality" {
                    guard let key = query["pbk"], !key.isEmpty else { throw Failure.invalid("Reality requires a public key.") }
                    node["reality-opts"] = ["public-key": Node(key, Tag(.str)), "short-id": Node(query["sid"] ?? "", Tag(.str))]
                } else if query["pbk"] != nil || query["sid"] != nil { throw Failure.invalid("Reality options require Reality security.") }
                let transport = query["type"] ?? "tcp"
                guard ["tcp", "ws", "grpc"].contains(transport) else { throw Failure.invalid("Unsupported transport. Use YAML import.") }
                if transport != "tcp" { node["network"] = Node(transport, Tag(.str)) }
                if transport == "ws" {
                    var options: Node = ["path": Node(query["path"] ?? "/", Tag(.str))]
                    if let host = query["host"] { options["headers"] = ["Host": Node(host, Tag(.str))] }; node["ws-opts"] = options
                } else if transport == "grpc" { node["grpc-opts"] = ["grpc-service-name": Node(query["serviceName"] ?? "", Tag(.str))] }
                if transport != "ws", query["path"] != nil || query["host"] != nil { throw Failure.invalid("WebSocket options require WebSocket transport.") }
                if transport != "grpc", query["serviceName"] != nil { throw Failure.invalid("gRPC options require gRPC transport.") }
            }
            try validateNode(node); result[name] = try yaml(node)
        }
        guard !result.isEmpty else { throw Failure.invalid("Paste at least one node link.") }
        return result
    }
}
