import Foundation

nonisolated enum MITMDomainMatcher {
    static let mitmBypassDomains: Set<String> = [
        "googleads.g.doubleclick.net",
        "pagead2.googlesyndication.com",
        "adservice.google.com",
        "google-analytics.com",
        "googleadservices.com",
        "static.doubleclick.net",
        "ad.doubleclick.net",
        "cm.g.doubleclick.net",
        "ade.googlesyndication.com",
        "tpc.googlesyndication.com",
        "mads.amazon-adsystem.com",
        "securepubads.g.doubleclick.net"
    ]

    static func normalizedPatterns(from rawValue: String) -> [String] {
        rawValue.components(separatedBy: CharacterSet(charactersIn: ",，\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }

    static func host(_ host: String, matches patterns: some Sequence<String>) -> Bool {
        let hostLower = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !hostLower.isEmpty else { return false }

        for rawPattern in patterns {
            let pattern = rawPattern.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !pattern.isEmpty else { continue }

            if hostLower == pattern || hostLower.hasSuffix("." + pattern) {
                return true
            }

            if pattern.hasPrefix("*") {
                let suffix = String(pattern.dropFirst())
                if hostLower.hasSuffix(suffix) {
                    return true
                }
            }
        }

        return false
    }
}
