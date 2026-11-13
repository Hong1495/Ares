import Foundation

/// mihomo /dns/query returns DNS records, not the selected upstream, proxy-host resolver or a decision trace.
nonisolated struct DNSQueryResult: Decodable, Sendable {
    struct Record: Decodable, Sendable {
        let name: String
        let type: Int
        let TTL: UInt32
        let data: String
        var typeName: String { DNSQueryResult.typeNames[type] ?? String(type) }
    }
    let Status: Int
    let TC: Bool
    let Answer: [Record]?
    let Authority: [Record]?
    let Additional: [Record]?
    static let types = ["A", "AAAA", "CNAME", "MX", "TXT", "NS", "SOA", "HTTPS", "SVCB", "PTR"]
    static let typeNames = [1: "A", 28: "AAAA", 5: "CNAME", 15: "MX", 16: "TXT", 2: "NS", 6: "SOA", 65: "HTTPS", 64: "SVCB", 12: "PTR"]
    var statusName: String {
        [0: "NOERROR", 1: "FORMERR", 2: "SERVFAIL", 3: "NXDOMAIN", 4: "NOTIMP", 5: "REFUSED"][Status] ?? "RCODE \(Status)"
    }
    static func request(base: String, name: String, type: String) throws -> URLRequest {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = name.hasSuffix(".") ? String(name.dropLast()) : name
        guard !trimmed.isEmpty, trimmed.utf8.count <= 253, types.contains(type),
              trimmed.split(separator: ".", omittingEmptySubsequences: false).allSatisfy({ !$0.isEmpty && $0.utf8.count <= 63 }),
              name.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._")).contains($0) }),
              var components = URLComponents(string: base + "/dns/query") else { throw URLError(.badURL) }
        components.queryItems = [URLQueryItem(name: "name", value: name), URLQueryItem(name: "type", value: type)]
        guard let url = components.url else { throw URLError(.badURL) }
        return URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
    }
}
