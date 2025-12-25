import Foundation
// import SwiftyJSON - Removed to use standard JSONSerialization

struct AIModelUsage: Identifiable, Equatable {
    let id: String
    let timestamp: Date
    let model: String
    let provider: String
    let inputTokens: Int
    let outputTokens: Int
    let latency: TimeInterval
    let status: Int
    
    var totalTokens: Int { inputTokens + outputTokens }
}

struct AIQuotaStatus: Identifiable, Equatable, Sendable {
    let id: String // "provider/model"
    let provider: String
    let model: String
    
    // Request Limits
    var requestsLimit: Int?
    var requestsRemaining: Int?
    var requestsResetTime: Date?
    
    // Token Limits
    var tokensLimit: Int?
    var tokensRemaining: Int?
    var tokensResetTime: Date?
    
    var lastUpdated: Date
}

class AIAnalysisService {
    static let shared = AIAnalysisService()
    
    // Discovery Mode: Log unknown quota headers for debugging
    var onDiscoveryLog: ((String) -> Void)?
    
    private init() {}
    
    func analyze(request: BrowserRequest) -> AIModelUsage? {
        // Only analyze completed requests/responses
        // guard request.status == .success || request.statusCode == 200 else { return nil }
        
        let url = request.url.lowercased()
        // method intentionally ignored - URL pattern matching is sufficient
        
        // 0. DEBUG: Log ALL unique hosts to help user identify traffic
        if let host = URL(string: request.url)?.host {
            DispatchQueue.main.async {
                // Using a static set to avoid spamming the same host. 
                // Note: This is a temporary debug helper.
                if !AIAnalysisService.seenHosts.contains(host) {
                    AIAnalysisService.seenHosts.insert(host)
                    let msg = "🆕 New Host Detected: \(host) (Path: \(request.url))"
                    print("[AIAnalysisService] \(msg)")
                    self.onDiscoveryLog?(msg)
                }
            }
        }
        
        // 1. Anthropic
        if url.contains("anthropic.com") && url.contains("messages") {
            return parseAnthropic(request)
        }
        
        // 2. OpenAI
        if url.contains("openai.com") && url.contains("completions") {
             return parseOpenAI(request)
        }
        
        // 3. Google (Vertex/Gemini)
        if url.contains("googleapis.com") || url.contains("gemini") || url.contains("generativelanguage") {
            return parseGoogle(request)
        }
        
        // 4. Eagle (Internal Proxy)
        if url.contains("eagle") {
            return parseEagle(request)
        }

        // 5. Generic "Model" key detection (for custom proxies etc)
        if let body = request.requestBody, body.contains("\"model\"") {
            return parseGeneric(request)
        }
        
        return nil
    }
    
    func parseQuota(request: BrowserRequest) -> AIQuotaStatus? {
        guard let headers = request.responseHeaders else { return nil }
        
        // Basic filtering for "Antigravity" context (can be refined via Process check later)
        // For now, we assume if we are analyzing it in this view, it's relevant.
        // But we want to avoid Browser noise. Check User-Agent?
        // let ua = request.requestHeaders?.first(where: { $0.key == "User-Agent" })?.value ?? ""
        // if ua.contains("Mozilla") { return nil } // Rough filter for browsers?
        
        let lowerHeaders = Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) })
        
        // Discovery Logging
        logDiscoveryHeaders(lowerHeaders, source: request.url)
        
        // 1. OpenAI
        if request.url.contains("openai") {
            return parseOpenAIQuota(lowerHeaders)
        }
        
        // 2. Anthropic
        if request.url.contains("anthropic") {
            return parseAnthropicQuota(lowerHeaders)
        }
        
        // 3. Google / General
        if request.url.contains("google") || request.url.contains("googleapis") {
            return parseGoogleQuota(lowerHeaders)
        }
        
        // 4. Fallback: Check for generic AI signatures ("model" in body, or "chat/completions" in URL)
        // This handles custom proxies like 10.10.25.251
        if isPotentialAIRequest(request) {
            // Even if we don't know the provider, we try to find rate headers
            let host = URL(string: request.url)?.host ?? "generic"
            if let q = parseGenericQuota(lowerHeaders, host: host) {
                return q
            }
        }
        
        return nil
    }

    private func isPotentialAIRequest(_ req: BrowserRequest) -> Bool {
        let url = req.url.lowercased()
        if url.contains("completions") || url.contains("generate") || url.contains("chat") || url.contains("eagle") { return true }
        if let body = req.requestBody, body.contains("\"model\"") { return true }
        return false
    }

    private func parseGenericQuota(_ h: [String: String], host: String) -> AIQuotaStatus? {
        // Try to find *any* standard rate limit header
        if let remaining = h["x-ratelimit-remaining"] ?? h["x-ratelimit-remaining-requests"] {
             return AIQuotaStatus(
                id: host, 
                provider: "Custom API",
                model: host, // Display host as model name for clarity
                requestsLimit: Int(h["x-ratelimit-limit"] ?? ""),
                requestsRemaining: Int(remaining),
                requestsResetTime: parseResetTime(h["x-ratelimit-reset"]),
                tokensLimit: nil,
                tokensRemaining: nil,
                tokensResetTime: nil,
                lastUpdated: Date()
            )
        }
        return nil
    }
    
    private func logDiscoveryHeaders(_ headers: [String: String], source: String) {
        // Aggressive logging: If we see "limit" or "quota", OR if the source looks like AI
        let quotaKeys = headers.keys.filter { key in
            key.contains("rate") || key.contains("limit") || key.contains("quota") || key.contains("remaining")
        }
        
        if !quotaKeys.isEmpty {
            let msg = "Start Discovery [\(source)]:\n" + quotaKeys.map { "- \($0): \(headers[$0] ?? "")" }.joined(separator: "\n")
            print("[AIAnalysisService] 🔍 \(msg)") // Console visibility
            DispatchQueue.main.async {
                self.onDiscoveryLog?(msg)
            }
        } else if source.contains("completions") || source.contains("generate") || source.contains("eagle") {
             // If it looks like AI but has no quota headers, log that fact
             let msg = "Potential AI Activity [\(source)]\nNo standard rate-limit headers found."
             print("[AIAnalysisService] ⚠️ \(msg)") // Console visibility
             DispatchQueue.main.async {
                self.onDiscoveryLog?(msg)
            }
        }
    }
    
    // Debug helper
    static var seenHosts = Set<String>()

    // MARK: - Providers
    
    private func parseAnthropic(_ req: BrowserRequest) -> AIModelUsage? {
        // Request: {"model": "claude-3-..."}
        // Response: {"usage": {"input_tokens": 10, "output_tokens": 20}}
        
        guard let reqBody = req.requestBody,
              let resBody = req.responseBody,
              let reqJson = try? JSONSerialization.jsonObject(with: Data(reqBody.utf8)) as? [String: Any],
              let resJson = try? JSONSerialization.jsonObject(with: Data(resBody.utf8)) as? [String: Any] else {
            return nil
        }
        
        let model = reqJson["model"] as? String ?? "Claude (Unknown)"
        
        var input = 0
        var output = 0
        
        if let usage = resJson["usage"] as? [String: Any] {
            input = usage["input_tokens"] as? Int ?? 0
            output = usage["output_tokens"] as? Int ?? 0
        }
        
        return AIModelUsage(
            id: req.id,
            timestamp: req.timestamp,
            model: model,
            provider: "Anthropic",
            inputTokens: input,
            outputTokens: output,
            latency: req.duration ?? 0,
            status: req.statusCode ?? 0
        )
    }
    
    private func parseOpenAI(_ req: BrowserRequest) -> AIModelUsage? {
        guard let reqBody = req.requestBody,
              let resBody = req.responseBody,
              let reqJson = try? JSONSerialization.jsonObject(with: Data(reqBody.utf8)) as? [String: Any],
              let resJson = try? JSONSerialization.jsonObject(with: Data(resBody.utf8)) as? [String: Any] else {
            return nil
        }
        
        let model = reqJson["model"] as? String ?? "GPT (Unknown)"
        
        var input = 0
        var output = 0
        
        if let usage = resJson["usage"] as? [String: Any] {
            input = usage["prompt_tokens"] as? Int ?? 0
            output = usage["completion_tokens"] as? Int ?? 0
        }
        
        return AIModelUsage(
            id: req.id,
            timestamp: req.timestamp,
            model: model,
            provider: "OpenAI",
            inputTokens: input,
            outputTokens: output,
            latency: req.duration ?? 0,
            status: req.statusCode ?? 0
        )
    }
    
    private func parseGoogle(_ req: BrowserRequest) -> AIModelUsage? {
        // Can be URL path (publishers/google/models/gemini-pro:streamGenerateContent)
        // Body usually has "contents"
        
        var model = "Gemini/PaLM"
        
        // Try to extract model from URL
        let pattern = "models/([^/:]+)"
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: req.url, range: NSRange(req.url.startIndex..., in: req.url)) {
            if let range = Range(match.range(at: 1), in: req.url) {
                model = String(req.url[range])
            }
        }
        
        // Check body for overrides
        if let reqBody = req.requestBody,
           let reqJson = try? JSONSerialization.jsonObject(with: Data(reqBody.utf8)) as? [String: Any],
           let m = reqJson["model"] as? String {
            model = m
        }
        
        // Usage metadata often at end of stream or in responseObj["usageMetadata"]
        var input = 0
        var output = 0
        
        if let resBody = req.responseBody {
            // Google often streams multiple JSON objects. We need to find "usageMetadata"
            // It might be in the last chunk.
            
            // Simple check: Look for "usageMetadata": { "promptTokenCount": 123, "candidatesTokenCount": 456 }
            // Using regex for robustness against streaming chunks
            // "usageMetadata"\s*:\s*\{\s*"promptTokenCount"\s*:\s*(\d+)
            
            let promptRegex = "promptTokenCount\"\\s*:\\s*(\\d+)"
            let candRegex = "candidatesTokenCount\"\\s*:\\s*(\\d+)" // or totalTokenCount
            
            if let pVal = findInt(pattern: promptRegex, in: resBody) { input = pVal }
            if let cVal = findInt(pattern: candRegex, in: resBody) { output = cVal }
            
            // If zero, maybe estimate? 
            if input == 0 && output == 0 {
                 input = (req.requestBody?.count ?? 0) / 4
                 output = resBody.count / 4
                 if input > 0 { model += " (Est)" }
            }
        }
        
        return AIModelUsage(
            id: req.id,
            timestamp: req.timestamp,
            model: model,
            provider: "Google",
            inputTokens: input,
            outputTokens: output,
            latency: req.duration ?? 0,
            status: req.statusCode ?? 0
        )

    }
    
    // MARK: - Quota Parsers
    
    private func parseOpenAIQuota(_ h: [String: String]) -> AIQuotaStatus? {
        // x-ratelimit-remaining-requests
        // x-ratelimit-remaining-tokens
        // x-ratelimit-reset-requests
        // x-ratelimit-reset-tokens
        
        guard h["x-ratelimit-remaining-requests"] != nil || h["x-ratelimit-remaining-tokens"] != nil else { return nil }
        
        return AIQuotaStatus(
            id: "openai",
            provider: "OpenAI",
            model: "Global",
            requestsLimit: Int(h["x-ratelimit-limit-requests"] ?? ""),
            requestsRemaining: Int(h["x-ratelimit-remaining-requests"] ?? ""),
            requestsResetTime: parseResetTime(h["x-ratelimit-reset-requests"]),
            tokensLimit: Int(h["x-ratelimit-limit-tokens"] ?? ""),
            tokensRemaining: Int(h["x-ratelimit-remaining-tokens"] ?? ""),
            tokensResetTime: parseResetTime(h["x-ratelimit-reset-tokens"]),
            lastUpdated: Date()
        )
    }
    
    private func parseAnthropicQuota(_ h: [String: String]) -> AIQuotaStatus? {
        guard h["anthropic-ratelimit-requests-remaining"] != nil else { return nil }
        
        return AIQuotaStatus(
            id: "anthropic",
            provider: "Anthropic",
            model: "Global",
            requestsLimit: Int(h["anthropic-ratelimit-requests-limit"] ?? ""),
            requestsRemaining: Int(h["anthropic-ratelimit-requests-remaining"] ?? ""),
            requestsResetTime: parseResetTime(h["anthropic-ratelimit-requests-reset"]),
            tokensLimit: Int(h["anthropic-ratelimit-tokens-limit"] ?? ""),
            tokensRemaining: Int(h["anthropic-ratelimit-tokens-remaining"] ?? ""),
            tokensResetTime: parseResetTime(h["anthropic-ratelimit-tokens-reset"]),
            lastUpdated: Date()
        )
    }
    
    private func parseGoogleQuota(_ h: [String: String]) -> AIQuotaStatus? {
        // Search for standard x-ratelimit and google variants
        let reqRem = h["x-ratelimit-remaining"] ?? h["x-ratelimit-remaining-requests"]
        // Google sometimes uses a simple "X-RateLimit-Remaining" for the primary quota (often RPM)
        
        guard let rem = reqRem else { return nil }
        
        return AIQuotaStatus(
            id: "google",
            provider: "Google",
            model: "Global",
            requestsLimit: Int(h["x-ratelimit-limit"] ?? ""),
            requestsRemaining: Int(rem),
            requestsResetTime: parseResetTime(h["x-ratelimit-reset"]),
            tokensLimit: nil,
            tokensRemaining: nil,
            tokensResetTime: nil,
            lastUpdated: Date()
        )
    }
    
    private func parseResetTime(_ value: String?) -> Date? {
        guard let v = value else { return nil }
        
        // Try parsing as seconds (e.g. "20ms", "6s") or epoch
        if v.hasSuffix("ms") {
            if let ms = Double(v.dropLast(2)) { return Date().addingTimeInterval(ms / 1000) }
        } else if v.hasSuffix("s") {
            if let s = Double(v.dropLast(1)) { return Date().addingTimeInterval(s) }
        }
        
        // Try int (seconds or epoch?)
        if let i = Double(v) {
            if i > 1700000000 { // Epoch
                return Date(timeIntervalSince1970: i)
            } else { // Relative seconds
                return Date().addingTimeInterval(i)
            }
        }
        return nil
    }
    
    private func parseEagle(_ req: BrowserRequest) -> AIModelUsage? {
        // Eagle Internal Proxy Analysis
        // Structure: { result: [ { HisDataItems: [ ... ] } ] }
        
        guard let resBody = req.responseBody else { return nil }
        
        // Ensure we can parse the string as JSON
        guard let data = resBody.data(using: .utf8),
              let resJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // print("🦅 Eagle Parse: Failed to parse JSON")
            return nil
        }
        
        guard let result = resJson["result"] as? [[String: Any]] else {
            // print("🦅 Eagle Parse: 'result' array missing or invalid")
            return nil
        }
        
        // Count total items fetched
        var totalItems = 0
        for item in result {
            if let hisItems = item["HisDataItems"] as? [Any] {
                totalItems += hisItems.count
            }
        }
        
        print("[AIAnalysisService] 🦅 Eagle Parsed: \(totalItems) items from \(req.url)")

        return AIModelUsage(
            id: req.id,
            timestamp: req.timestamp,
            model: "Eagle/History",
            provider: "Internal",
            inputTokens: 0,
            outputTokens: totalItems, 
            latency: req.duration ?? 0,
            status: req.statusCode ?? 0
        )
    }

    private func parseGeneric(_ req: BrowserRequest) -> AIModelUsage? {
        guard let reqBody = req.requestBody,
              let reqJson = try? JSONSerialization.jsonObject(with: Data(reqBody.utf8)) as? [String: Any],
              let model = reqJson["model"] as? String else {
            return nil
        }
        
        // Guess usage
        let input = (req.requestBody?.count ?? 0) / 4
        let output = (req.responseBody?.count ?? 0) / 4
        
        return AIModelUsage(
            id: req.id,
            timestamp: req.timestamp,
            model: model,
            provider: "Unknown",
            inputTokens: input,
            outputTokens: output,
            latency: req.duration ?? 0,
            status: req.statusCode ?? 0
        )
    }
    
    private func findInt(pattern: String, in text: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        if let match = regex.firstMatch(in: text, range: range),
           let r = Range(match.range(at: 1), in: text),
           let val = Int(text[r]) {
            return val
        }
        return nil
    }
}
