import Foundation

/// mihomo v1.19.34 /rules. Counters are optional; absence is not zero.
nonisolated struct ClashRule: Codable, Identifiable, Sendable {
    let index: Int
    let type: String
    let payload: String
    let proxy: String
    let extra: Extra?
    var id: Int { index }
    var hit: UInt64? { extra?.hitCount }
    struct Extra: Codable, Sendable {
        let disabled: Bool
        let hitCount: UInt64
    }
    static func decode(_ data: Data) throws -> [ClashRule] {
        struct Response: Decodable { let rules: [ClashRule] }
        let rules = try JSONDecoder().decode(Response.self, from: data).rules
        guard Set(rules.map(\.index)).count == rules.count, rules.allSatisfy({ $0.index >= 0 }) else {
            throw URLError(.cannotParseResponse)
        }
        return rules.sorted { $0.index < $1.index }
    }
}

nonisolated struct RuleProvider: Decodable, Identifiable, Sendable {
    let name: String
    let behavior: String
    let vehicleType: String
    let ruleCount: Int
    let updatedAt: String?
    var id: String { name }
    var canUpdate: Bool { vehicleType.lowercased() != "inline" }
    var updatedDate: Date? {
        guard let updatedAt, !updatedAt.hasPrefix("0001-") else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: updatedAt) ?? ISO8601DateFormatter().date(from: updatedAt)
    }
    static func decode(_ data: Data) throws -> [RuleProvider] {
        struct Response: Decodable { let providers: [String: RuleProvider] }
        let values = try JSONDecoder().decode(Response.self, from: data).providers
        guard values.allSatisfy({ $0.key == $0.value.name && $0.value.ruleCount >= 0 }) else {
            throw URLError(.cannotParseResponse)
        }
        return values.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
