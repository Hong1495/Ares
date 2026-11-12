import Foundation
import Darwin

/// Converts the shared bypass/host preferences into core rule predicates.
nonisolated enum SettingsRouting {
    static func predicate(for raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var ipv4 = in_addr()
        var ipv6 = in6_addr()
        if inet_pton(AF_INET, value, &ipv4) == 1 { return "IP-CIDR,\(value)/32" }
        if inet_pton(AF_INET6, value, &ipv6) == 1 { return "IP-CIDR6,\(value)/128" }
        if value.contains("/") { return "\(value.contains(":") ? "IP-CIDR6" : "IP-CIDR"),\(value)" }
        let pieces = value.split(separator: ".", omittingEmptySubsequences: false)
        if pieces.last == "*", (2...4).contains(pieces.count),
           pieces.dropLast().allSatisfy({ Int($0).map { (0...255).contains($0) } ?? false }) {
            let prefix = pieces.dropLast().map(String.init)
            return "IP-CIDR,\((prefix + Array(repeating: "0", count: 4 - prefix.count)).joined(separator: "."))/\(prefix.count * 8)"
        }
        let domain = value.hasPrefix("*.") ? String(value.dropFirst(2)) : value
        return "DOMAIN-SUFFIX,\(domain)"
    }
}
