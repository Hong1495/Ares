import Foundation
import Darwin

nonisolated struct ExitIdentity: Equatable, Sendable {
    let ip: String
    let country: String?

    static func isAddress(_ value: String) -> Bool {
        var v4 = in_addr()
        var v6 = in6_addr()
        return inet_pton(AF_INET, value, &v4) == 1 || inet_pton(AF_INET6, value, &v6) == 1
    }

    static func parse(_ data: Data, status: Int) -> Self? {
        guard (200..<300).contains(status) else { return nil }
        var ip: String?
        var country: String?
        if let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            ip = json["ip"] as? String ?? json["address"] as? String
            country = json["country_code"] as? String ?? json["country_iso"] as? String ?? json["country"] as? String
        } else if let text = String(data: data, encoding: .utf8) {
            for line in text.split(separator: "\n") {
                let pair = line.split(separator: "=", maxSplits: 1)
                guard pair.count == 2 else { continue }
                if pair[0] == "ip" { ip = String(pair[1]) }
                if pair[0] == "loc" { country = String(pair[1]) }
            }
        }
        guard let ip, isAddress(ip) else { return nil }
        let code = country?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let validCode = code.flatMap { value in
            value.utf8.count == 2 && value.utf8.allSatisfy { (65...90).contains($0) } ? value : nil
        }
        return Self(ip: ip, country: validCode)
    }
}
