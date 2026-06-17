import Foundation

nonisolated enum CoreArchiveExtractor {
    static func zipEntriesAreSafe(_ entries: [String]) -> Bool {
        entries.allSatisfy { entry in
            let normalized = entry.replacingOccurrences(of: "\\", with: "/")
            guard !normalized.isEmpty,
                  !normalized.hasPrefix("/"),
                  !normalized.contains("\0") else {
                return false
            }

            return !normalized
                .split(separator: "/", omittingEmptySubsequences: false)
                .contains("..")
        }
    }

    static func findCoreBinary(in directory: URL, fileManager: FileManager = .default) throws -> URL? {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var candidates: [(url: URL, score: Int)] = []
        for case let url as URL in enumerator {
            guard !url.pathComponents.contains("__MACOSX") else { continue }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  let score = candidateScore(for: url.lastPathComponent) else {
                continue
            }
            candidates.append((url, score))
        }

        return candidates.sorted {
            if $0.score != $1.score {
                return $0.score > $1.score
            }
            if $0.url.pathComponents.count != $1.url.pathComponents.count {
                return $0.url.pathComponents.count < $1.url.pathComponents.count
            }
            return $0.url.lastPathComponent.count < $1.url.lastPathComponent.count
        }.first?.url
    }

    private static func candidateScore(for fileName: String) -> Int? {
        let lower = fileName.lowercased()
        guard lower.contains("mihomo") || lower.contains("clash") else {
            return nil
        }
        guard !lower.hasSuffix(".sha256"),
              !lower.hasSuffix(".sig"),
              !lower.hasSuffix(".txt"),
              !lower.hasSuffix(".md"),
              !lower.hasSuffix(".json"),
              !lower.hasSuffix(".yaml"),
              !lower.hasSuffix(".yml") else {
            return nil
        }

        var score = 0
        if lower == "mihomo" || lower == "clash-meta" { score += 100 }
        if lower.hasPrefix("mihomo") { score += 60 }
        if lower.hasPrefix("clash") { score += 40 }
        if lower.contains("darwin") { score += 20 }
        if lower.contains("arm64") { score += 20 }
        if lower.contains("compatible") { score -= 10 }
        if lower.contains("-go") { score -= 10 }
        return score
    }
}
