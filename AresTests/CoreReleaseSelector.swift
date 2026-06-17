import Foundation

nonisolated enum CoreReleaseSelector {
    static func parseDisplayVersion(from raw: String) -> String {
        guard !raw.isEmpty else { return "Unknown" }
        if let range = raw.range(of: #"v\d+\.\d+\.\d+"#, options: .regularExpression) {
            return String(raw[range])
        }
        return raw.components(separatedBy: .newlines).first ?? "Unknown"
    }

    static func isUpdateAvailable(current: String, latest: String) -> Bool {
        compareVersions(latest, current) == .orderedDescending
    }

    static func selectDarwinARM64Asset(from assets: [(name: String, url: URL)]) -> (name: String, url: URL)? {
        var fallback: (name: String, url: URL)?

        for asset in assets {
            let lower = asset.name.lowercased()
            guard lower.contains("darwin"),
                  lower.contains("arm64"),
                  lower.hasSuffix(".gz") || lower.hasSuffix(".zip") else {
                continue
            }

            if !lower.contains("-go") && !lower.contains("compatible") {
                return asset
            }
            fallback = fallback ?? asset
        }

        return fallback
    }

    private static func normalizedVersion(_ version: String) -> [Int] {
        version
            .replacingOccurrences(of: "v", with: "")
            .split(separator: ".")
            .map { Int($0) ?? 0 }
    }

    private static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = normalizedVersion(lhs)
        let right = normalizedVersion(rhs)
        let count = max(left.count, right.count)

        for index in 0..<count {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l > r { return .orderedDescending }
            if l < r { return .orderedAscending }
        }

        return .orderedSame
    }
}
