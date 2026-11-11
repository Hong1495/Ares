import Foundation

/// Pure API decoding; a node exists before its first latency measurement.
nonisolated enum ProxySnapshot {
    static func decode(_ data: Data) throws -> (groups: [ProxyGroup], nodes: [String: ProxyNode]) {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let proxies = json["proxies"] as? [String: [String: Any]] else {
            throw URLError(.cannotParseResponse)
        }
        var groups: [ProxyGroup] = []
        var nodes: [String: ProxyNode] = [:]
        for (name, proxy) in proxies {
            guard let type = proxy["type"] as? String else { continue }
            let history = proxy["history"] as? [[String: Any]]
            nodes[name] = ProxyNode(id: name, name: name, type: type, delay: history?.last?["delay"] as? Int)
            if let all = proxy["all"] as? [String] {
                groups.append(ProxyGroup(name: name, type: type, now: proxy["now"] as? String, all: all))
            }
        }
        return (groups.sorted { $0.name < $1.name }, nodes)
    }
}
