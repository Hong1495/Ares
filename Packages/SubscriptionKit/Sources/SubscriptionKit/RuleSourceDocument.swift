import Foundation
import Yams

/// Rule-only projection of a verified configuration. Never exposes provider URLs, proxy credentials or arbitrary YAML.
public enum RuleSourceDocument {
    public struct Row: Identifiable, Sendable {
        public let id: String
        public let location: String
        public let rule: String
        public let origin: String
        public let providers: [String]
        public let subRules: [String]
    }
    public struct Document: Sendable {
        public let rows: [Row]
        public let providerNames: [String]
        public let issues: [String]
        public func references(to name: String) -> [Row] { rows.filter { $0.providers.contains(name) } }
    }
    public static func read(configuration: String, subscription: String?, localRules: String?) throws -> Document {
        // Reuse the production parser for duplicate keys, aliases and document shape.
        func parse(_ text: String) throws -> Node {
            let normalized = try EffectiveConfiguration.build(source: text, defaults: "{}", overrides: [])
            guard let root = try Yams.compose(yaml: normalized) else { throw EffectiveConfiguration.BuildError.invalidDocument }
            return root
        }
        func strings(_ node: Node?) throws -> [String] {
            guard let node else { return [] }
            guard let list = node.sequence else { throw EffectiveConfiguration.BuildError.invalidSection }
            return try list.map { item in
                guard let value = item.string else { throw EffectiveConfiguration.BuildError.invalidSection }
                return value
            }
        }
        let root = try parse(configuration)
        let original = try subscription.map(parse)
        let rules = try strings(root["rules"])
        let sourceRules = try strings(original?["rules"])
        let local = localRules.map { RuleDraftDocument($0).rules.compactMap(\.rule) } ?? []
        let hasSourceSuffix = original != nil && rules.count >= sourceRules.count && Array(rules.suffix(sourceRules.count)) == sourceRules
        let sourceStart = hasSourceSuffix ? rules.count - sourceRules.count : rules.count
        let hasLocalPrefix = localRules != nil && local.count <= sourceStart && Array(rules.prefix(local.count)) == local
        var rows: [Row] = []
        var issues: [String] = []
        func row(_ raw: String, location: String, origin: String) -> Row {
            let refs = references(raw)
            if !refs.complete { issues.append("\(location): some expression references could not be interpreted.") }
            return Row(id: location, location: location, rule: raw, origin: origin,
                       providers: refs.providers.sorted(), subRules: refs.subRules.sorted())
        }
        for (index, raw) in rules.enumerated() {
            let origin = index >= sourceStart && hasSourceSuffix ? "Subscription" :
                (hasLocalPrefix && index < local.count ? "Local override" : "Verified configuration")
            rows.append(row(raw, location: "rules[\(index + 1)]", origin: origin))
        }
        if let sub = root["sub-rules"] {
            guard let mapping = sub.mapping else { throw EffectiveConfiguration.BuildError.invalidSection }
            for (key, node) in mapping {
                guard let name = key.string else { throw EffectiveConfiguration.BuildError.invalidSection }
                let entries = try strings(node)
                let inherited = original?["sub-rules"]?[name] == node
                for (index, raw) in entries.enumerated() {
                    rows.append(row(raw, location: "sub-rules[\(name)][\(index + 1)]", origin: inherited ? "Subscription" : "Verified configuration"))
                }
            }
        }
        var names: [String] = []
        if let providers = root["rule-providers"] {
            guard let mapping = providers.mapping else { throw EffectiveConfiguration.BuildError.invalidSection }
            for (key, _) in mapping {
                guard let name = key.string else { throw EffectiveConfiguration.BuildError.invalidSection }
                names.append(name)
            }
        }
        // Every sub-rule section is listed independently, including unreferenced ones; no recursive truncation.
        return Document(rows: rows, providerNames: names.sorted(), issues: issues)
    }

    private struct References {
        var providers = Set<String>()
        var subRules = Set<String>()
        var complete = true
    }
    private static func references(_ rule: String) -> References {
        var result = References()
        func split(_ text: String) -> [String]? {
            var depth = 0, start = text.startIndex, items: [String] = []
            for i in text.indices {
                if text[i] == "(" { depth += 1 }
                if text[i] == ")" { depth -= 1; if depth < 0 { return nil } }
                if text[i] == ",", depth == 0 { items.append(String(text[start..<i])); start = text.index(after: i) }
            }
            guard depth == 0 else { return nil }
            items.append(String(text[start...]))
            return items.map { $0.trimmingCharacters(in: .whitespaces) }
        }
        func inspect(_ text: String, depth: Int) {
            // Defensive parsing bound, explicitly reported instead of silently omitting references.
            guard depth < 128, let parts = split(text), let type = parts.first else { result.complete = false; return }
            if type == "RULE-SET", parts.count >= 2 { result.providers.insert(parts[1]); return }
            if type == "SUB-RULE", parts.count >= 3 { result.subRules.insert(parts[2]) }
            guard ["AND", "OR", "NOT", "SUB-RULE"].contains(type) else { return }
            guard parts.count >= 2 else { result.complete = false; return }
            let expression = parts[1]
            guard expression.first == "(", expression.last == ")" else { result.complete = false; return }
            let inner = String(expression.dropFirst().dropLast())
            if inner.first == "(" {
                guard let children = split(inner) else { result.complete = false; return }
                for child in children {
                    guard child.first == "(", child.last == ")" else { result.complete = false; continue }
                    inspect(String(child.dropFirst().dropLast()), depth: depth + 1)
                }
            } else { inspect(inner, depth: depth + 1) }
        }
        inspect(rule, depth: 0)
        return result
    }
}
