import Foundation

/// Service responsible for analyzing network traffic to detect and parse AI interactions.
class AIAnalysisService {
    static let shared = AIAnalysisService()
    
    // Callbacks
    var onDiscoveryLog: ((String) -> Void)?
    var onModelListUpdate: (([AntigravityModelInfo]) -> Void)?
    
    private init() {}
    
    // MARK: - Main Analysis Entry Point
    
    func analyze(request: BrowserRequest) -> AIModelUsage? {
        let url = request.url.lowercased()
        
        // 1. Specialized: Antigravity Model List (Priority)
        if url.contains("fetchavailablemodels") {
            parseAvailableModels(request)
            return nil
        }
        
        // 2. Specialized: Antigravity IDE Usage
        // (Often googleapis.com/v1internal/...)
        if (url.contains("google") || url.contains("gemini")) {
            // Check for specific markers of IDE traffic
            if url.contains("fetchuserinfo") || url.contains("loadcodeassist") { return nil } // Ignore noise
            
            if let usage = parseAntigravityIDE(request) {
                return usage
            }
        }
        
        // 3. Third-Party Providers
        if url.contains("anthropic.com") && url.contains("messages") {
            return parseAnthropic(request)
        }
        
        if url.contains("openai.com") && url.contains("completions") {
             return parseOpenAI(request)
        }
        
        if url.contains("eagle") {
             return parseEagle(request)
        }
        
        // 4. Fallback Generic
        if let body = request.requestBody, body.contains("\"model\"") {
            return parseGeneric(request)
        }
        
        return nil
    }
    
    func parseQuota(request: BrowserRequest) -> AIQuotaStatus? {
        guard let headers = request.responseHeaders else { return nil }
        // Fix: Use uniquingKeysWith to avoid crash on duplicate case-insensitive keys
        let lowerHeaders = Dictionary(headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { (first, _) in first })
        
        // Log potential new headers for discovery
        logDiscoveryHeaders(lowerHeaders, source: request.url)
        
        if request.url.contains("openai") { return parseOpenAIQuota(lowerHeaders) }
        if request.url.contains("anthropic") { return parseAnthropicQuota(lowerHeaders) }
        if request.url.contains("google") || request.url.contains("googleapis") { return parseGoogleQuota(lowerHeaders) }
        
        return nil
    }

    // MARK: - Antigravity Parsers
    
    private func parseAvailableModels(_ req: BrowserRequest) {
        guard let resBody = req.responseBody,
              let data = resBody.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let modelsDict = json["models"] as? [String: [String: Any]] else {
            return
        }
        
        print("[AIAnalysisService] ✅ Found \(modelsDict.count) models in Antigravity response")
        
        let models: [AntigravityModelInfo] = modelsDict.compactMap { (key, dict) in
            let displayName = dict["displayName"] as? String ?? key
            
            var quota: AntigravityQuotaInfo?
            if let qDict = dict["quotaInfo"] as? [String: Any] {
                quota = AntigravityQuotaInfo(
                    remainingFraction: qDict["remainingFraction"] as? Double,
                    resetTime: qDict["resetTime"] as? String
                )
            }
            
            return AntigravityModelInfo(
                id: key,
                displayName: displayName,
                quotaInfo: quota,
                recommended: dict["recommended"] as? Bool,
                maxTokens: dict["maxTokens"] as? Int,
                apiProvider: dict["apiProvider"] as? String
            )
        }
        
        DispatchQueue.main.async {
            self.onModelListUpdate?(models)
        }
    }
    
    private func parseAntigravityIDE(_ req: BrowserRequest) -> AIModelUsage? {
        guard let resBody = req.responseBody,
              let data = resBody.data(using: .utf8),
              let resJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        
        // Case A: { "models": ... } payload
        if let models = resJson["models"] as? [String: Any], let key = models.keys.first {
            return estimateUsage(req, model: key, provider: "Google (AG)")
        }
        
        // Case B: { "response": { "candidates": ... } }
        if let response = resJson["response"] as? [String: Any],
           response["candidates"] != nil {
            return estimateUsage(req, model: "Gemini/Vertex", provider: "Google (AG)")
        }
        
        return nil
    }
    
    private func estimateUsage(_ req: BrowserRequest, model: String, provider: String) -> AIModelUsage {
        let inputEst = (req.requestBody?.count ?? 0) / 4
        let outputEst = (req.responseBody?.count ?? 0) / 4
        return AIModelUsage(
            id: req.id, timestamp: req.timestamp, model: model, provider: provider,
            inputTokens: inputEst, outputTokens: outputEst,
            latency: req.duration ?? 0, status: req.statusCode ?? 200
        )
    }

    // MARK: - Other Parsers (Private)

    private func parseAnthropic(_ req: BrowserRequest) -> AIModelUsage? {
        guard let data = req.responseBody?.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let usage = json["usage"] as? [String: Any] else { return nil }
              
        return AIModelUsage(
            id: req.id, timestamp: req.timestamp, model: "Claude", provider: "Anthropic",
            inputTokens: usage["input_tokens"] as? Int ?? 0,
            outputTokens: usage["output_tokens"] as? Int ?? 0,
            latency: req.duration ?? 0, status: req.statusCode ?? 200
        )
    }
    
    private func parseOpenAI(_ req: BrowserRequest) -> AIModelUsage? {
        guard let data = req.responseBody?.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let usage = json["usage"] as? [String: Any] else { return nil }
              
        return AIModelUsage(
            id: req.id, timestamp: req.timestamp, model: "GPT", provider: "OpenAI",
            inputTokens: usage["prompt_tokens"] as? Int ?? 0,
            outputTokens: usage["completion_tokens"] as? Int ?? 0,
            latency: req.duration ?? 0, status: req.statusCode ?? 200
        )
    }
    
    private func parseEagle(_ req: BrowserRequest) -> AIModelUsage? {
        guard let data = req.responseBody?.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [[String: Any]] else { return nil }
              
        let count = result.reduce(0) { $0 + (($1["HisDataItems"] as? [Any])?.count ?? 0) }
        return AIModelUsage(
            id: req.id, timestamp: req.timestamp, model: "Eagle", provider: "Internal",
            inputTokens: 0, outputTokens: count,
            latency: req.duration ?? 0, status: req.statusCode ?? 200
        )
    }
    
    private func parseGeneric(_ req: BrowserRequest) -> AIModelUsage? {
        // Fallback guess
        guard let body = req.requestBody,
              let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let model = json["model"] as? String else { return nil }
              
        return estimateUsage(req, model: model, provider: "Generic")
    }
    
    // MARK: - Quota Parsers
    
    private func parseOpenAIQuota(_ h: [String: String]) -> AIQuotaStatus? {
        guard h["x-ratelimit-remaining-requests"] != nil else { return nil }
        return AIQuotaStatus(id: "openai", provider: "OpenAI", model: "Global",
                             requestsLimit: Int(h["x-ratelimit-limit-requests"] ?? ""),
                             requestsRemaining: Int(h["x-ratelimit-remaining-requests"] ?? ""),
                             requestsResetTime: nil,
                             tokensLimit: Int(h["x-ratelimit-limit-tokens"] ?? ""),
                             tokensRemaining: Int(h["x-ratelimit-remaining-tokens"] ?? ""),
                             tokensResetTime: nil, lastUpdated: Date())
    }
    
    private func parseAnthropicQuota(_ h: [String: String]) -> AIQuotaStatus? {
        guard h["anthropic-ratelimit-requests-remaining"] != nil else { return nil }
         return AIQuotaStatus(id: "anthropic", provider: "Anthropic", model: "Global",
                             requestsLimit: Int(h["anthropic-ratelimit-requests-limit"] ?? ""),
                             requestsRemaining: Int(h["anthropic-ratelimit-requests-remaining"] ?? ""),
                             requestsResetTime: nil,
                             tokensLimit: Int(h["anthropic-ratelimit-tokens-limit"] ?? ""),
                             tokensRemaining: Int(h["anthropic-ratelimit-tokens-remaining"] ?? ""),
                             tokensResetTime: nil, lastUpdated: Date())
    }
    
    private func parseGoogleQuota(_ h: [String: String]) -> AIQuotaStatus? {
        guard let rem = h["x-ratelimit-remaining"] ?? h["x-ratelimit-remaining-requests"] else { return nil }
         return AIQuotaStatus(id: "google", provider: "Google", model: "Global",
                             requestsLimit: Int(h["x-ratelimit-limit"] ?? ""),
                             requestsRemaining: Int(rem),
                             requestsResetTime: nil,
                             tokensLimit: nil,
                             tokensRemaining: nil,
                             tokensResetTime: nil, lastUpdated: Date())
    }

    private func logDiscoveryHeaders(_ headers: [String: String], source: String) {
        let quotaKeys = headers.keys.filter { $0.contains("rate") || $0.contains("limit") || $0.contains("quota") }
        if !quotaKeys.isEmpty {
            let msg = "Discovery [\(source)]: " + quotaKeys.joined(separator: ", ")
            DispatchQueue.main.async { self.onDiscoveryLog?(msg) }
        }
    }
}
