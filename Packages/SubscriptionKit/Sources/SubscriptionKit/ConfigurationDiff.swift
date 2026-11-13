import Foundation
import Yams

/// Structural diff of complete YAML documents. Comments and mapping order are ignored;
/// sequence order remains meaningful. No limit or truncation is applied to changed fields.
public enum ConfigurationDiff {
    public struct Row: Sendable, Identifiable {
        public let id: Int
        public let path: String
        public let before: String
        public let after: String
        public let change: String
    }
    public enum Failure: LocalizedError {
        case invalidDocument
        public var errorDescription: String? { "The configurations could not be compared." }
    }

    public static func compare(before: String, after: String) throws -> [Row] {
        do {
            let lhs = try normalized(before)
            let rhs = try normalized(after)
            var rows: [Row] = []
            walk(lhs, rhs, path: [], label: "", rows: &rows)
            return rows
        } catch { throw Failure.invalidDocument }
    }

    private static func normalized(_ text: String) throws -> Node {
        let yaml = try EffectiveConfiguration.build(source: text, defaults: "{}", overrides: [])
        guard let node = try Yams.compose(yaml: yaml) else { throw Failure.invalidDocument }
        return node
    }

    private static func walk(_ lhs: Node?, _ rhs: Node?, path: [String], label: String, rows: inout [Row]) {
        if let left = lhs?.mapping, let right = rhs?.mapping {
            let keys = Set(left.keys.compactMap(\.string)).union(right.keys.compactMap(\.string)).sorted()
            for (index, key) in keys.enumerated() {
                let component = visibleKeys.contains(key) ? key : "<field \(index + 1)>"
                walk(left[key], right[key], path: path + [key], label: label.isEmpty ? component : label + "." + component, rows: &rows)
            }
            return
        }
        if let left = lhs?.sequence, let right = rhs?.sequence {
            for index in 0..<max(left.count, right.count) {
                walk(index < left.count ? left[index] : nil, index < right.count ? right[index] : nil,
                     path: path + ["[]"], label: label + "[\(index + 1)]", rows: &rows)
            }
            return
        }
        guard lhs != rhs else { return }
        // Expand additions/removals too, so users can account for every changed leaf.
        if lhs == nil, let map = rhs?.mapping, !map.isEmpty {
            for (index, item) in map.sorted(by: { ($0.key.string ?? "") < ($1.key.string ?? "") }).enumerated() {
                let key = item.key.string ?? ""
                let component = visibleKeys.contains(key) ? key : "<field \(index + 1)>"
                walk(nil, item.value, path: path + [key], label: label + "." + component, rows: &rows)
            }
            return
        }
        if rhs == nil, let map = lhs?.mapping, !map.isEmpty {
            for (index, item) in map.sorted(by: { ($0.key.string ?? "") < ($1.key.string ?? "") }).enumerated() {
                let key = item.key.string ?? ""
                let component = visibleKeys.contains(key) ? key : "<field \(index + 1)>"
                walk(item.value, nil, path: path + [key], label: label + "." + component, rows: &rows)
            }
            return
        }
        if lhs == nil, let sequence = rhs?.sequence, !sequence.isEmpty {
            for (index, value) in sequence.enumerated() { walk(nil, value, path: path + ["[]"], label: label + "[\(index + 1)]", rows: &rows) }
            return
        }
        if rhs == nil, let sequence = lhs?.sequence, !sequence.isEmpty {
            for (index, value) in sequence.enumerated() { walk(value, nil, path: path + ["[]"], label: label + "[\(index + 1)]", rows: &rows) }
            return
        }
        rows.append(Row(id: rows.count, path: label, before: display(lhs, path: path), after: display(rhs, path: path),
                        change: lhs == nil ? "Added" : rhs == nil ? "Removed" : "Changed"))
    }

    // Paths may contain domains, provider names or custom keys: unknown keys are masked too.
    private static let visibleKeys: Set<String> = [
        "port", "socks-port", "mixed-port", "mode", "log-level", "allow-lan", "ipv6", "external-controller", "secret",
        "keep-alive-interval", "udp-timeout", "tcp-concurrent", "unified-delay", "find-process-mode", "global-client-fingerprint",
        "tun", "enable", "stack", "mtu", "device", "auto-route", "auto-detect-interface", "dns-hijack", "route-address", "route-exclude-address",
        "dns", "nameserver", "nameserver-policy", "proxy-server-nameserver", "direct-nameserver", "fallback", "fallback-filter",
        "default-nameserver", "enhanced-mode", "fake-ip-range", "fake-ip-filter", "respect-rules", "listen",
        "sniffer", "sniff", "TLS", "HTTP", "QUIC", "ports", "force-domain", "skip-domain",
        "profile", "store-selected", "store-fake-ip", "proxies", "proxy-groups", "proxy-providers", "rules", "rule-providers",
        "name", "type", "server", "password", "uuid", "url", "path", "interval", "tolerance", "lazy", "use", "filter", "health-check",
        "client-fingerprint", "dialer-proxy", "listeners", "tunnels", "hosts", "geox-url", "geoip", "geosite", "payload", "behavior"
    ]
    private static func display(_ node: Node?, path: [String]) -> String {
        guard let node else { return "—" }
        if let map = node.mapping { return "Mapping (\(map.count))" }
        if let sequence = node.sequence { return "List (\(sequence.count))" }
        // Only application-known public setting paths are allowed to disclose values.
        let safe: Set<String> = ["port", "socks-port", "mixed-port", "mode", "log-level", "allow-lan", "ipv6",
            "keep-alive-interval", "udp-timeout", "tcp-concurrent", "unified-delay", "find-process-mode",
            "tun.enable", "tun.stack", "tun.mtu", "tun.auto-route", "tun.auto-detect-interface",
            "dns.enable", "dns.ipv6", "sniffer.enable", "profile.store-selected", "profile.store-fake-ip"]
        guard safe.contains(path.joined(separator: ".")), let scalar = node.scalar else { return "Hidden" }
        if node.tag == Tag(.bool) || node.tag == Tag(.int) { return scalar.string }
        let enums: Set<String> = ["rule", "global", "direct", "silent", "error", "warning", "info", "debug", "always", "strict", "off", "system", "mixed", "gvisor"]
        return enums.contains(scalar.string) ? scalar.string : "Hidden"
    }
}
