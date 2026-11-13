import Foundation
import Yams

/// Per-subscription group composition. Legacy parameter-only overrides remain compatible; unknown source fields survive.
public enum PolicyConfiguration {
    public struct Group: Identifiable, Sendable {
        public let name: String
        public let type: String
        public let members: [String]
        public let providers: [String]
        public let fields: [String: String]
        public var id: String { name }
    }
    public static let types = ["select", "url-test", "fallback", "load-balance"]
    public static let structuralFields = ["_create", "_delete", "type", "proxies", "use", "url"]
    public struct Catalog: Sendable {
        public let nodes: [String]
        public let providers: [String]
    }
    public enum Failure: LocalizedError {
        case invalid(String)
        public var errorDescription: String? { switch self { case .invalid(let text): return text } }
    }
    public static func catalog(_ source: String) throws -> Catalog {
        let root = try parse(source)
        return Catalog(nodes: (root["proxies"]?.sequence ?? []).compactMap { $0["name"]?.string }.sorted(),
                       providers: (root["proxy-providers"]?.mapping ?? [:]).compactMap { $0.key.string }.sorted())
    }
    public static func list(_ values: [String]) throws -> String {
        String(decoding: try JSONEncoder().encode(values), as: UTF8.self)
    }
    public static func list(_ value: String) throws -> [String] {
        try JSONDecoder().decode([String].self, from: Data(value.utf8))
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
            for field in fields + ["url", "exclude-type", "include-all", "include-all-proxies", "include-all-providers"] { if let value = node[field]?.scalar?.string { values[field] = value } }
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
        try compose(source: source, overrides: overrides, strict: true)
    }
    /// Repair view only: retains stale edited groups so subscription updates cannot lock the editor out.
    public static func preview(source: String, overrides: String) throws -> String {
        try compose(source: source, overrides: overrides, strict: false)
    }
    private static func compose(source: String, overrides: String, strict: Bool) throws -> String {
        let edits = try decodeOverrides(overrides)
        if edits.isEmpty { return source }
        var root = try parse(source)
        var sequence = Array(root["proxy-groups"]?.sequence ?? [])
        let originalNames = Set(sequence.compactMap { $0["name"]?.string })
        let builtins = Set(["DIRECT", "REJECT", "REJECT-DROP", "PASS", "COMPATIBLE", "GLOBAL"])
        let nodes = Set((root["proxies"]?.sequence ?? []).compactMap { $0["name"]?.string })
        for name in edits.keys.sorted() {
            let values = edits[name]!
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !name.contains(","), !name.contains("\n"), !builtins.contains(name), !nodes.contains(name),
                  Set(values.keys).isSubset(of: Set(fields + structuralFields)) else {
                throw Failure.invalid("Invalid group name or unsupported override fields: " + name)
            }
            if let flag = values["_create"], flag != "true" { throw Failure.invalid("Invalid creation flag.") }
            if let flag = values["_delete"], flag != "true" { throw Failure.invalid("Invalid deletion flag.") }
            if values["_delete"] == "true" {
                guard values.count == 1 else { throw Failure.invalid("Deleted groups cannot also carry overrides.") }
                sequence.removeAll { $0["name"]?.string == name }; continue
            }
            let index = sequence.firstIndex { $0["name"]?.string == name }
            if values["_create"] == "true", originalNames.contains(name), strict {
                throw Failure.invalid("A local group now conflicts with a subscription group: " + name + ". Rename or restore inheritance.")
            }
            if index == nil, values["_create"] != "true", strict {
                throw Failure.invalid("Edited group is missing from the subscription: " + name + ". Remove its stale override.")
            }
            var result: Node = index.map { sequence[$0] } ?? ["name": Node(name, Tag(.str))]
            let oldType = result["type"]?.string
            let type = values["type"] ?? oldType ?? "select"
            guard types.contains(type) else { throw Failure.invalid("Unsupported group type: " + type) }
            if oldType != nil && oldType != type {
                // Remove only parameters owned by a different group algorithm. Preserve unknown source fields.
                let removed = Set(fields.filter { !editableFields(type: type).contains($0) })
                result = .mapping(.init((result.mapping ?? [:]).filter { !removed.contains($0.key.string ?? "") }.map { ($0.key, $0.value) }))
            }
            result["type"] = Node(type, Tag(.str))
            for key in ["proxies", "use"] {
                if let value = values[key] {
                    let items = try list(value)
                    guard Set(items).count == items.count, items.allSatisfy({ !$0.isEmpty }) else { throw Failure.invalid("Duplicate or empty members in " + name) }
                    result[key] = .sequence(.init(items.map { Node($0, Tag(.str), .doubleQuoted) }))
                }
            }
            if values["_create"] == "true", index == nil, type != "select" {
                result["url"] = Node("https://www.gstatic.com/generate_204", Tag(.str))
                result["interval"] = Node("300", Tag(.int))
            }
            if let url = values["url"] {
                guard let parsed = URL(string: url), ["http", "https"].contains(parsed.scheme), parsed.host != nil else { throw Failure.invalid("Use an HTTP or HTTPS probe URL.") }
                result["url"] = Node(url, Tag(.str), .doubleQuoted)
            }
            for (key, value) in values where fields.contains(key) {
                guard editableFields(type: type).contains(key) else {
                    if !strict { continue }
                    throw Failure.invalid("Parameter " + key + " does not apply to " + type)
                }
                switch key {
                case "interval", "timeout", "tolerance":
                    guard let number = UInt32(value), (key != "timeout" || number > 0), (key != "tolerance" || number <= UInt16.max) else { throw Failure.invalid("Invalid time or tolerance in " + name) }
                    result[key] = Node(String(number), Tag(.int))
                case "lazy":
                    guard ["true", "false"].contains(value) else { throw Failure.invalid("Lazy must be true or false.") }
                    result[key] = Node(value, Tag(.bool))
                case "strategy":
                    guard ["consistent-hashing", "round-robin", "sticky-sessions"].contains(value) else { throw Failure.invalid("Invalid load-balancing strategy.") }
                    result[key] = Node(value, Tag(.str))
                default: result[key] = Node(value, Tag(.str), .doubleQuoted)
                }
            }
            if let index { sequence[index] = result } else { sequence.append(result) }
        }
        root["proxy-groups"] = .sequence(.init(sequence))
        if strict { try validate(root) }
        return try Yams.serialize(node: root, allowUnicode: true)
    }
    private static func validate(_ root: Node) throws {
        let groups = Array(root["proxy-groups"]?.sequence ?? [])
        let nodes = Array(root["proxies"]?.sequence ?? [])
        let names = groups.compactMap { $0["name"]?.string } + nodes.compactMap { $0["name"]?.string }
        guard Set(names).count == names.count else { throw Failure.invalid("Group and node names must be unique.") }
        let targets = Set(names + ["DIRECT", "REJECT", "REJECT-DROP", "PASS", "COMPATIBLE"])
        let providers = Set((root["proxy-providers"]?.mapping ?? [:]).compactMap { $0.key.string })
        var edges: [String: [String]] = [:]
        for group in groups {
            let name = group["name"]!.string!
            let members = try strings(group["proxies"]), uses = try strings(group["use"])
            guard Set(members).isSubset(of: targets) else { throw Failure.invalid("Missing member in " + name + ". Review subscription changes and group references.") }
            guard Set(uses).isSubset(of: providers) else { throw Failure.invalid("Missing node resource in " + name) }
            let includes = ["include-all", "include-all-proxies", "include-all-providers"].contains { group[$0]?.bool == true }
            guard !members.isEmpty || !uses.isEmpty || includes else { throw Failure.invalid("Add a member or node resource to " + name) }
            edges[name] = members
        }
        for node in nodes {
            if let dialer = node["dialer-proxy"]?.string, !dialer.isEmpty {
                guard targets.contains(dialer) else { throw Failure.invalid("Missing dialer group: " + dialer) }
                edges[node["name"]!.string!] = [dialer]
            }
        }
        var done = Set<String>()
        for start in edges.keys where !done.contains(start) {
            var active = Set<String>(), stack: [(String, Bool)] = [(start, false)]
            while let (name, leaving) = stack.popLast() {
                if leaving { active.remove(name); done.insert(name); continue }
                if active.contains(name) { throw Failure.invalid("Circular policy dependency involving " + name) }
                if done.contains(name) { continue }
                active.insert(name); stack.append((name, true))
                for child in edges[name] ?? [] where edges[child] != nil { stack.append((child, false)) }
            }
        }
        // The pinned core validates rule targets (including logical/sub-rule syntax), filters,
        // listeners and provider-expanded graphs against the final merged document.
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
