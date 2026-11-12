import Foundation
import CoreFoundation

nonisolated struct IPReputation: Equatable, Sendable {
    let ip: String
    let risk: Int
    let types: [String]
    let checkedAt: Date

    static func parse(_ data: Data, status: Int, ip: String, now: Date = Date()) -> Self? {
        guard (200..<300).contains(status), ExitIdentity.isAddress(ip),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              ["ok", "warning"].contains(root["status"] as? String ?? ""),
              let address = root[ip] as? [String: Any],
              let detections = address["detections"] as? [String: Any],
              let score = detections["risk"] as? NSNumber,
              CFGetTypeID(score) != CFBooleanGetTypeID(),
              score.doubleValue.rounded() == score.doubleValue,
              (0...100).contains(score.intValue) else { return nil }
        let fields = [("proxy", "Proxy"), ("vpn", "VPN"), ("tor", "Tor"),
                      ("hosting", "Hosting"), ("compromised", "Compromised"), ("scraper", "Scraper")]
        return Self(ip: ip, risk: score.intValue,
                    types: fields.compactMap { detections[$0.0] as? Bool == true ? $0.1 : nil }, checkedAt: now)
    }
}
