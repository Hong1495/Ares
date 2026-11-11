import Foundation

nonisolated enum SubscriptionPayload {
    static func prepare(data: Data, response: URLResponse, validate: (String) async throws -> Bool) async throws -> String {
        try CoreAPIContract.requireSuccess(response)
        guard let text = String(data: data, encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<"),
              (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")?.lowercased().contains("text/html") != true else {
            throw URLError(.cannotParseResponse)
        }
        // Conversion must never depend on subscription-userinfo headers.
        let content = SubscriptionConverter.convert(content: text) ?? text
        let json = content.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let hasNodes = content.range(of: #"(?m)^(?:proxies|proxy-providers)\s*:"#, options: .regularExpression) != nil
            || json?["proxies"] != nil || json?["proxy-providers"] != nil
        guard hasNodes, try await validate(content) else {
            throw NSError(domain: "Subscription", code: 1, userInfo: [NSLocalizedDescriptionKey: "Subscription is not a valid Clash configuration. The previous file was kept."])
        }
        return content
    }
}

/// A response can commit only if its profile still exists and its revision is current.
nonisolated struct ProfileUpdateRevisions {
    private var revisions: [UUID: UUID] = [:]
    mutating func begin(_ id: UUID) -> UUID {
        let token = UUID()
        revisions[id] = token
        return token
    }
    mutating func invalidate(_ id: UUID) { revisions.removeValue(forKey: id) }
    func isCurrent(_ token: UUID, for id: UUID) -> Bool { revisions[id] == token }
}
