import Foundation
import Yams
import Darwin

/// Subscription-scoped outbound fields and explicit whole-section inbound overrides.
public enum EgressConfiguration {
    public struct NodeInfo: Identifiable, Sendable {
        public let name: String
        public let type: String
        public let dialer: String
        public let interface: String
        public var id: String { name }
    }
    public struct Document: Sendable {
        public let nodes: [NodeInfo]
        public let targets: [String]
        public let interface: String
        public let listeners: String
        public let tunnels: String
    }
    public struct Overrides: Codable, Equatable, Sendable {
        public var nodes: [String: [String: String]] = [:]
        public var interface: String?
        public var listeners: String?
        public var tunnels: String?
        public init() {}
    }
    public struct Endpoint: Equatable, Sendable {
        public let transport: String
        public let host: String
        public let port: Int
        public init(transport: String, host: String, port: Int) { self.transport = transport; self.host = host; self.port = port }
    }
    public enum ValidationError: LocalizedError {
        case invalid, missingNode, reference, cycle, conflict
        public var errorDescription: String? {
            switch self {
            case .invalid: return "Invalid outbound or listener configuration. Check field types, addresses and ports."
            case .missingNode: return "An edited node no longer exists in this subscription. Reload before applying."
            case .reference: return "A proxy target is missing or unavailable in the saved configuration."
            case .cycle: return "The proxy chain contains a circular dependency."
            case .conflict: return "Listener ports overlap each other or an application-managed port."
            }
        }
    }
    public static func decode(_ text: String) throws -> Overrides {
        do { return try JSONDecoder().decode(Overrides.self, from: Data(text.utf8)) }
        catch { throw ValidationError.invalid }
    }
    public static func encode(_ value: Overrides) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }
    public static let empty = #"{"nodes":{}}"#
    public static func read(_ text: String) throws -> Document {
        let root = try parse(text)
        let nodes = try sequence(root["proxies"]).map { node -> NodeInfo in
            guard let name = node["name"]?.string, let type = node["type"]?.string else { throw ValidationError.invalid }
            return NodeInfo(name: name, type: type, dialer: node["dialer-proxy"]?.string ?? "", interface: node["interface-name"]?.string ?? "")
        }
        let groups = try sequence(root["proxy-groups"]).compactMap { $0["name"]?.string }
        return Document(nodes: nodes, targets: Array(Set(nodes.map(\.name) + groups + ["DIRECT"])).sorted(),
            interface: root["interface-name"]?.string ?? "", listeners: try yaml(root["listeners"] ?? []), tunnels: try yaml(root["tunnels"] ?? []))
    }
    public static func apply(source: String, overrides text: String) throws -> String {
        let edits = try decode(text)
        if edits == Overrides() { return source }
        var root = try parse(source)
        let nodes = try sequence(root["proxies"])
        let names = Set(nodes.compactMap { $0["name"]?.string })
        guard Set(edits.nodes.keys).isSubset(of: names) else { throw ValidationError.missingNode }
        root["proxies"] = .sequence(.init(try nodes.map { node in
            guard let name = node["name"]?.string else { throw ValidationError.invalid }
            var result = node
            for (key, value) in edits.nodes[name] ?? [:] {
                guard ["dialer-proxy", "interface-name"].contains(key) else { throw ValidationError.invalid }
                if key == "interface-name" { try validateInterface(value) }
                result[key] = Node(value, Tag(.str))
            }
            return result
        }))
        if let interface = edits.interface { try validateInterface(interface); root["interface-name"] = Node(interface, Tag(.str)) }
        if let listeners = edits.listeners { root["listeners"] = try section(listeners); try validateListeners(root) }
        if let tunnels = edits.tunnels { root["tunnels"] = try section(tunnels); try validateTunnels(root) }
        try validateGraph(root)
        let rendered = try yaml(root)
        try validatePorts(configuration: rendered)
        return rendered
    }
    private static func validateInterface(_ value: String) throws {
        guard value.utf8.count < Int(IFNAMSIZ), value.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-").contains($0) }) else { throw ValidationError.invalid }
    }
    private static func validateGraph(_ root: Node) throws {
        let nodes = try sequence(root["proxies"]), groups = try sequence(root["proxy-groups"])
        var graph: [String: [String]] = [:]
        for node in nodes + groups {
            guard let name = node["name"]?.string, graph[name] == nil else { throw ValidationError.invalid }
            var edges = try sequence(node["proxies"]).compactMap(\.string)
            if let dialer = node["dialer-proxy"]?.string, !dialer.isEmpty { edges.append(dialer) }
            graph[name] = edges
        }
        for node in nodes {
            if let dialer = node["dialer-proxy"]?.string, !dialer.isEmpty, dialer != "DIRECT", graph[dialer] == nil { throw ValidationError.reference }
        }
        // Iterative DFS: include all static group members, not only the current selection.
        var done = Set<String>()
        for start in graph.keys where !done.contains(start) {
            var active = Set<String>(), stack: [(String, Bool)] = [(start, false)]
            while let (name, leaving) = stack.popLast() {
                if leaving { active.remove(name); done.insert(name); continue }
                if active.contains(name) { throw ValidationError.cycle }
                if done.contains(name) { continue }
                active.insert(name); stack.append((name, true))
                for next in graph[name] ?? [] where graph[next] != nil { stack.append((next, false)) }
            }
        }
    }
    private static func targets(_ root: Node) throws -> Set<String> {
        Set(try (sequence(root["proxies"]) + sequence(root["proxy-groups"])).compactMap { $0["name"]?.string }).union(["DIRECT", "REJECT"])
    }
    private static func validateListeners(_ root: Node) throws {
        var names = Set<String>()
        let known = try targets(root)
        for item in try sequence(root["listeners"]) {
            guard let name = item["name"]?.string, !name.isEmpty, names.insert(name).inserted,
                  let type = item["type"]?.string, ["http", "socks", "mixed"].contains(type),
                  let host = item["listen"]?.string, isIP(host),
                  let port = item["port"]?.int, (1...65535).contains(port) else { throw ValidationError.invalid }
            if let udp = item["udp"], udp.tag != Tag(.bool) { throw ValidationError.invalid }
            if let proxy = item["proxy"]?.string, !proxy.isEmpty, !known.contains(proxy) { throw ValidationError.reference }
            if let rule = item["rule"]?.string, !rule.isEmpty, root["sub-rules"]?[rule] == nil { throw ValidationError.reference }
            // Preserve all existing fields, including TLS and auth; core validates their semantics.
            if let users = item["users"] {
                for user in try sequence(users) {
                    guard user["username"]?.tag == Tag(.str), user["password"]?.tag == Tag(.str), !(user["username"]?.string ?? "").isEmpty else { throw ValidationError.invalid }
                }
            }
        }
    }
    private static func validateTunnels(_ root: Node) throws {
        let known = try targets(root)
        for item in try sequence(root["tunnels"]) {
            let value = try tunnel(item)
            guard !value.0.isEmpty, Set(value.0).count == value.0.count, value.0.allSatisfy({ ["tcp", "udp"].contains($0) }), isIP(value.1.0) else { throw ValidationError.invalid }
            if !value.3.isEmpty, !known.contains(value.3) { throw ValidationError.reference }
        }
    }
    private static func tunnel(_ node: Node) throws -> ([String], (String, Int), (String, Int), String) {
        if let text = node.string {
            let parts = text.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard [3, 4].contains(parts.count) else { throw ValidationError.invalid }
            return (parts[0].components(separatedBy: "/"), try address(parts[1]), try address(parts[2]), parts.count == 4 ? parts[3] : "")
        }
        guard let from = node["address"]?.string, let to = node["target"]?.string else { throw ValidationError.invalid }
        let networkNodes = try sequence(node["network"])
        guard networkNodes.allSatisfy({ $0.tag == Tag(.str) }) else { throw ValidationError.invalid }
        let networks = networkNodes.compactMap(\.string)
        return (networks, try address(from), try address(to), node["proxy"]?.string ?? "")
    }
    private static func address(_ text: String) throws -> (String, Int) {
        guard let split = text.lastIndex(of: ":"), let port = Int(text[text.index(after: split)...]), (1...65535).contains(port) else { throw ValidationError.invalid }
        var host = String(text[..<split])
        if host.hasPrefix("[") && host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        if host.isEmpty { host = "0.0.0.0" }
        guard !host.contains(where: { $0.isWhitespace }), !host.contains(":") || isIP(host) else { throw ValidationError.invalid }
        return (host, port)
    }
    public static func isIP(_ host: String) -> Bool {
        var v4 = in_addr(), v6 = in6_addr()
        return host.withCString { inet_pton(AF_INET, $0, &v4) == 1 || inet_pton(AF_INET6, $0, &v6) == 1 }
    }
    /// Projection of supported single-port inbounds. Complex inherited listeners stay core-owned.
    public static func endpoints(configuration: String) throws -> [Endpoint] {
        let root = try parse(configuration)
        var result: [Endpoint] = []
        for item in try sequence(root["listeners"]) {
            guard let type = item["type"]?.string, ["http", "socks", "mixed"].contains(type),
                  let port = item["port"]?.int, (1...65535).contains(port) else { continue }
            let host = item["listen"]?.string ?? "0.0.0.0"
            result.append(Endpoint(transport: "tcp", host: host, port: port))
            if type != "http", item["udp"]?.bool != false { result.append(Endpoint(transport: "udp", host: host, port: port)) }
        }
        for item in try sequence(root["tunnels"]) {
            let value = try tunnel(item)
            result += value.0.map { Endpoint(transport: $0, host: value.1.0, port: value.1.1) }
        }
        return result
    }
    public static func validatePorts(configuration: String) throws {
        let root = try parse(configuration)
        var used = try endpoints(configuration: configuration)
        for key in ["port", "socks-port", "mixed-port", "redir-port", "tproxy-port"] {
            if let port = root[key]?.int, port > 0 {
                used.append(Endpoint(transport: "tcp", host: "*", port: port))
                if key != "port" { used.append(Endpoint(transport: "udp", host: "*", port: port)) }
            }
        }
        for key in ["external-controller", "external-controller-tls"] {
            if let text = root[key]?.string, let value = try? address(text) { used.append(Endpoint(transport: "tcp", host: "*", port: value.1)) }
        }
        if let text = root["dns"]?["listen"]?.string, root["dns"]?["enable"]?.bool == true, let value = try? address(text) {
            used += ["tcp", "udp"].map { Endpoint(transport: $0, host: "*", port: value.1) }
        }
        for i in used.indices {
            for j in used.indices where j > i && used[i].port == used[j].port && used[i].transport == used[j].transport {
                let a = used[i].host, b = used[j].host
                if a == b || ["*", "0.0.0.0", "::"].contains(a) || ["*", "0.0.0.0", "::"].contains(b) { throw ValidationError.conflict }
            }
        }
    }
    private static func section(_ text: String) throws -> Node {
        let root = try parse("value:\n" + text.components(separatedBy: .newlines).map { "  " + $0 }.joined(separator: "\n"))
        guard let value = root["value"], value.sequence != nil else { throw ValidationError.invalid }; return value
    }
    private static func sequence(_ node: Node?) throws -> [Node] {
        guard let node else { return [] }; guard let seq = node.sequence else { throw ValidationError.invalid }; return Array(seq)
    }
    private static func yaml(_ node: Node) throws -> String { try Yams.serialize(node: node, allowUnicode: true).trimmingCharacters(in: .whitespacesAndNewlines) }
    private static func parse(_ text: String) throws -> Node {
        guard let node = try Yams.compose(yaml: EffectiveConfiguration.build(source: text, defaults: "{}", overrides: [])) else { throw ValidationError.invalid }; return node
    }
}
