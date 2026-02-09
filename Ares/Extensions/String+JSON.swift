import Foundation

extension String {
    /// Check if content looks like JSON (handles chunked residue, SSE, and Google XSSI)
    var looksLikeJSON: Bool {
        let trimmed = self.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") { return true }
        if trimmed.hasPrefix("data:") { return true } // SSE / EventStream
        if trimmed.hasPrefix(")]}'") { return true } // Google XSSI protection
        return false
    }

    /// Preprocess non-standard JSON (SSE, NDJSON, XSSI) into valid JSON
    var preprocessJSON: String {
        var processed = self.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Handle Google XSSI protection prefix
        if processed.hasPrefix(")]}'") {
            processed = String(processed.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // 2. Handle Server-Sent Events (SSE) "data: {...}"
        if processed.contains("data:") {
            let lines = processed.components(separatedBy: .newlines)
            var jsonItems: [String] = []
            var isSSE = false

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("data:") {
                    isSSE = true
                    let jsonPart = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                    // Skip [DONE] or empty data
                    if jsonPart != "[DONE]" && !jsonPart.isEmpty {
                        jsonItems.append(jsonPart)
                    }
                }
            }

            if isSSE && !jsonItems.isEmpty {
                // Wrap SSE events in a JSON array
                return "[\n" + jsonItems.joined(separator: ",\n") + "\n]"
            }
        }

        // 3. Handle NDJSON (Newline Delimited JSON) detection
        // If it starts with { and contains }\n{
        if processed.hasPrefix("{") && processed.contains("}\n{") {
           let lines = processed.components(separatedBy: .newlines)
           let validLines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
           if validLines.count > 1 {
               return "[\n" + validLines.joined(separator: ",\n") + "\n]"
           }
        }

        return processed
    }
}
