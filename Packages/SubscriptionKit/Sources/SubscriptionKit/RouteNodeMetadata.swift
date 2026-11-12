import Foundation
import Yams

/// Allowlisted routing metadata; never exports authentication fields or full YAML.
public struct RouteNodeMetadata: Sendable {
    public let name: String
    public let server: String
    public let type: String
    public let dialer: String?
    public static func parse(_ text: String) throws -> [Self] {
        guard let root = try Yams.load(yaml: text) as? [String: Any] else { throw SubscriptionSnapshot.ParseError.invalidDocument }
        return (root["proxies"] as? [[String: Any]] ?? []).compactMap { item in
            guard let name = item["name"] as? String, let type = item["type"] as? String,
                  let server = item["server"] as? String else { return nil }
            return Self(name: name, server: server, type: type, dialer: item["dialer-proxy"] as? String)
        }
    }
}
