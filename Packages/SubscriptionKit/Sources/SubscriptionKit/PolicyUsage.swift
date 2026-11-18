import Foundation
import Yams

/// Saved references, never proof that traffic matched a rule. No URLs, credentials
/// or provider contents are projected into this document.
public enum PolicyUsage {
    public struct Reference: Identifiable, Equatable, Sendable {
        public let id: String
        public let target: String
        public let kind: String
        public let name: String
        public let detail: String
    }
    public struct Document: Sendable {
        public let references: [Reference]
        public let issues: [String]
        public func references(to name: String) -> [Reference] { references.filter { $0.target == name } }
    }

    public static func read(source: String, localRules: String, egress: EgressConfiguration.Overrides = .init(),
                            devices: [DeviceAccess.Device] = []) throws -> Document {
        let normalized = try EffectiveConfiguration.build(source: source, defaults: "{}", overrides: [])
        guard let root = try Yams.compose(yaml: normalized) else { throw EffectiveConfiguration.BuildError.invalidDocument }
        var refs: [Reference] = [], issues: [String] = []
        func add(_ id: String, _ target: String?, _ kind: String, _ name: String, _ detail: String) {
            guard let target, !target.isEmpty else { return }
            refs.append(.init(id: id, target: target, kind: kind, name: name, detail: detail))
        }
        func rules(_ entries: [String], scope: String) {
            for (index, raw) in entries.enumerated() {
                guard let parts = split(raw), let type = parts.first, parts.count >= 2 else {
                    issues.append("\(scope) rule \(index + 1) could not be inspected."); continue
                }
                // SUB-RULE points to a rule section, not to an outbound policy.
                if type == "SUB-RULE" { continue }
                let targetIndex = parts.last == "no-resolve" ? parts.count - 2 : parts.count - 1
                // Match targets only for known grammar. Unknown expressions remain visible as
                // incomplete inspection instead of being silently counted as ordinary rules.
                let unary = ["MATCH", "FINAL"]
                let valued = ["DOMAIN", "DOMAIN-SUFFIX", "DOMAIN-KEYWORD", "DOMAIN-REGEX", "GEOSITE", "GEOIP", "IP-ASN", "IP-CIDR", "IP-CIDR6", "IP-SUFFIX", "SRC-GEOIP", "SRC-IP-ASN", "SRC-IP-CIDR", "SRC-IP-SUFFIX", "SRC-PORT", "DST-PORT", "IN-PORT", "IN-TYPE", "IN-USER", "IN-NAME", "PROCESS-PATH", "PROCESS-NAME", "PROCESS-PATH-REGEX", "PROCESS-NAME-REGEX", "NETWORK", "DSCP", "RULE-SET", "UID", "AND", "OR", "NOT"]
                guard ((unary.contains(type) && targetIndex == 1) || (valued.contains(type) && targetIndex == 2)),
                      !parts[targetIndex].isEmpty else {
                    issues.append("\(scope) rule \(index + 1) could not be inspected."); continue
                }
                let application = ["PROCESS-PATH", "PROCESS-NAME", "PROCESS-PATH-REGEX", "PROCESS-NAME-REGEX"].contains(type)
                let payload = parts.count > 2 ? parts[1] : type
                let name = application ? (payload as NSString).lastPathComponent : "\(scope) rule \(index + 1)"
                add("\(scope).\(index)", parts[targetIndex], application ? "Application" : "Rule", name,
                    application ? scope + " · " + type + " · " + payload : scope + " · " + type)
            }
        }
        rules(RuleDraftDocument(localRules).rules.compactMap(\.rule), scope: "Local")
        rules(try strings(root["rules"]), scope: "Subscription")
        if let sections = root["sub-rules"]?.mapping {
            for (key, node) in sections {
                guard let name = key.string else { throw EffectiveConfiguration.BuildError.invalidSection }
                rules(try strings(node), scope: "Sub-rule " + name)
            }
        }
        for group in root["proxy-groups"]?.sequence ?? [] {
            guard let name = group["name"]?.string else { continue }
            for (index, member) in try strings(group["proxies"]).enumerated() {
                add("group.\(name).\(index)", member, "Group", name, "Explicit member")
            }
            if ["include-all", "include-all-proxies", "include-all-providers"].contains(where: { group[$0]?.bool == true }) {
                issues.append(name + ": dynamic membership may add references at runtime.")
            }
        }
        for node in root["proxies"]?.sequence ?? [] {
            guard let name = node["name"]?.string else { continue }
            add("dialer." + name, egress.nodes[name]?["dialer-proxy"] ?? node["dialer-proxy"]?.string,
                "Chain", name, "Dialer policy")
        }
        for section in ["listeners", "tunnels"] {
            let override = section == "listeners" ? egress.listeners : egress.tunnels
            let node = try override.map { try Yams.compose(yaml: $0) } ?? root[section]
            for (index, item) in (node?.sequence ?? []).enumerated() {
                add("\(section).\(index)", item["proxy"]?.string, section == "listeners" ? "Listener" : "Tunnel",
                    item["name"]?.string ?? "\(section == "listeners" ? "Listener" : "Tunnel") \(index + 1)", "Configured route")
            }
        }
        for device in devices {
            add("device." + device.id.uuidString, device.target, "Device", device.name, device.enabled ? "Enabled" : "Disabled")
        }
        return Document(references: refs, issues: issues)
    }

    private static func strings(_ node: Node?) throws -> [String] {
        guard let node else { return [] }
        guard let entries = node.sequence else { throw EffectiveConfiguration.BuildError.invalidSection }
        return try entries.map { guard let value = $0.string else { throw EffectiveConfiguration.BuildError.invalidSection }; return value }
    }
    private static func split(_ text: String) -> [String]? {
        var depth = 0, start = text.startIndex, parts: [String] = []
        for i in text.indices {
            if text[i] == "(" { depth += 1 }
            if text[i] == ")" { depth -= 1; if depth < 0 { return nil } }
            if text[i] == ",", depth == 0 { parts.append(String(text[start..<i])); start = text.index(after: i) }
        }
        guard depth == 0 else { return nil }
        parts.append(String(text[start...]))
        return parts.map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
