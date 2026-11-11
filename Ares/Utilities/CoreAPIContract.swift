import Foundation

nonisolated enum CoreAPIContract {
    static func requireSuccess(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw NSError(domain: "CoreAPI", code: (response as? HTTPURLResponse)?.statusCode ?? -1,
                          userInfo: [NSLocalizedDescriptionKey: "Core request failed (HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1))"])
        }
    }

    static func proxyURL(base: String, name: String, delay: Bool = false, timeout: Int = 5000) throws -> URL {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        guard let segment = name.addingPercentEncoding(withAllowedCharacters: allowed),
              var url = URLComponents(string: "\(base)/proxies/\(segment)\(delay ? "/delay" : "")") else { throw URLError(.badURL) }
        if delay { url.queryItems = [URLQueryItem(name: "timeout", value: "\(timeout)"), URLQueryItem(name: "url", value: "http://www.gstatic.com/generate_204")] }
        guard let result = url.url else { throw URLError(.badURL) }
        return result
    }

    static func verifyTUN(_ data: Data, expected: Bool) throws {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tun = json["tun"] as? [String: Any], let actual = tun["enable"] as? Bool,
              actual == expected else {
            throw NSError(domain: "CoreAPI", code: -2, userInfo: [NSLocalizedDescriptionKey: "Core TUN state could not be verified"])
        }
    }

    static func connections(_ data: Data) throws -> [String: Any] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["connections"] is [[String: Any]] else { throw URLError(.cannotParseResponse) }
        return json
    }
}
