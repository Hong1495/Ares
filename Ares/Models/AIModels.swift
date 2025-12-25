import Foundation

// MARK: - Core Data Models

struct AIModelUsage: Identifiable, Equatable, Sendable {
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

// MARK: - Antigravity API Models

struct AntigravityModelInfo: Identifiable, Codable, Sendable {
    let id: String
    let displayName: String
    let quotaInfo: AntigravityQuotaInfo?
    let recommended: Bool?
    let maxTokens: Int?
    let apiProvider: String?
}

struct AntigravityQuotaInfo: Codable, Sendable {
    let remainingFraction: Double?
    let resetTime: String?
}
