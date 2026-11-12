import Foundation

/// Removes only settings owned by Ares. Nested node/provider settings are opaque.
nonisolated enum ProfileConfigMerge {
    private static let ownedKeys: Set<String> = [
        "mixed-port", "socks-port", "port", "mode", "log-level", "allow-lan",
        "ipv6", "external-controller", "secret", "keep-alive-interval",
        "tcp-concurrent", "unified-delay", "global-client-fingerprint",
        "find-process-mode", "udp-timeout", "mptcp",
        "tun", "profile", "dns", "sniffer"
    ]

    static func removingOverrides(from content: String) -> String {
        var skipping = false
        return content.components(separatedBy: .newlines).filter { line in
            if let key = rootKey(line) {
                skipping = ownedKeys.contains(key)
            }
            // An indentless sequence belongs to its preceding mapping key.
            return !skipping
        }.joined(separator: "\n")
    }

    private static func rootKey(_ line: String) -> String? {
        // YAML keys are case-sensitive; quoted keys are legal too.
        let pattern = #"^(?:"([^"]+)"|'([^']+)'|([A-Za-z0-9_-]+))\s*:(?:\s|$)"#
        guard let match = line.range(of: pattern, options: .regularExpression) else { return nil }
        let header = String(line[match]).trimmingCharacters(in: .whitespaces)
        return String(header.dropLast()).trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }
}
