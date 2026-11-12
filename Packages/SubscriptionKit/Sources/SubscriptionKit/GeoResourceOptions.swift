import Foundation
import Yams

/// Only the resource URL overrides; never exposes node credentials or subscription URLs.
public enum GeoResourceOptions {
    public static func urls(in text: String) throws -> [String: String] {
        guard let root = try Yams.load(yaml: text) as? [String: Any] else {
            throw SubscriptionSnapshot.ParseError.invalidDocument
        }
        return (root["geox-url"] as? [String: Any] ?? [:]).compactMapValues { $0 as? String }
    }
}
