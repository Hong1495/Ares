import Foundation

nonisolated struct RouteLocation: Codable, Equatable, Sendable {
    let longitude: Double
    let latitude: Double
    let label: String
    let precision: String
    var coordinate: [Double] { [longitude, latitude] }
}

nonisolated struct RouteEndpoint: Codable, Equatable, Sendable {
    let name: String
    let address: String
    let kind: String
    let evidence: String
    var location: RouteLocation?
}

nonisolated struct ObservedRoute: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let application: String
    let host: String
    let rule: String
    let chain: [String]
    let endpoints: [RouteEndpoint]
    var connections: Int
    var upload: Int64
    var download: Int64
    var hasLocation: Bool { endpoints.contains { $0.location != nil } }
    var hasMapLink: Bool { zip(endpoints, endpoints.dropFirst()).contains { $0.location != nil && $1.location != nil } }
}

nonisolated struct RouteSnapshot: Codable, Equatable, Sendable {
    var routes: [ObservedRoute] = []
    var connectionCount: Int { routes.reduce(0) { $0 + $1.connections } }
    var unlocatedCount: Int { routes.filter { !$0.hasLocation }.reduce(0) { $0 + $1.connections } }
    var upload: Int64 { routes.reduce(0) { $0 + $1.upload } }
    var download: Int64 { routes.reduce(0) { $0 + $1.download } }

    struct Input: Sendable {
        let id: String
        let application: String
        let host: String
        let destinationIP: String
        let rule: String
        let chains: [String]
        let upload: Int64
        let download: Int64
    }
    struct Node: Sendable {
        let name: String
        let server: String
        let type: String
        let dialer: String?
    }

    static func build(inputs: [Input], nodes: [String: Node], locations: [String: RouteLocation]) -> Self {
        var groups: [String: ObservedRoute] = [:]
        var seen = Set<String>()
        for input in inputs where seen.insert(input.id).inserted {
            // The core chain is retained verbatim. Group names are not geographic hops.
            // The first concrete adapter is the destination-side adapter; do not infer
            // hop order for multiple adapters from a presentation string.
            let concrete = input.chains.compactMap { nodes[$0] }
            var endpoints = [RouteEndpoint(name: input.application, address: "", kind: "application", evidence: "Observed process", location: nil)]
            if let node = concrete.first {
                if let dialer = node.dialer, !dialer.isEmpty {
                    endpoints.append(RouteEndpoint(name: dialer, address: "", kind: "unverified", evidence: "Configured upstream; runtime hop not confirmed", location: nil))
                }
                endpoints.append(RouteEndpoint(name: node.name, address: node.server, kind: "proxy", evidence: "Observed adapter · configured \(node.type) entry address", location: locations[node.server]))
                // Entry address does not establish the remote server's egress address.
                endpoints.append(RouteEndpoint(name: "Remote egress", address: "", kind: "unknown", evidence: "Not reported by the core", location: nil))
            } else if !input.chains.isEmpty && !input.chains.contains("DIRECT") && !input.chains.contains("REJECT") {
                endpoints.append(RouteEndpoint(name: input.chains.first ?? "Proxy", address: "", kind: "unknown", evidence: "Observed adapter · address unavailable", location: nil))
            }
            let host = input.host.isEmpty ? input.destinationIP : input.host
            endpoints.append(RouteEndpoint(name: host.isEmpty ? "Unknown destination" : host,
                address: input.destinationIP, kind: "destination", evidence: "Core-reported destination", location: locations[input.destinationIP]))
            // JSON array encoding makes separators in host/process/node names unambiguous.
            let identity = [input.application, host, input.destinationIP, input.rule] + input.chains
            let id = String(data: try! JSONEncoder().encode(identity), encoding: .utf8)!
            if var route = groups[id] {
                route.connections += 1; route.upload += input.upload; route.download += input.download
                groups[id] = route
            } else {
                groups[id] = ObservedRoute(id: id, application: input.application, host: host,
                    rule: input.rule, chain: input.chains, endpoints: endpoints, connections: 1,
                    upload: input.upload, download: input.download)
            }
        }
        return Self(routes: groups.values.sorted { $0.id < $1.id })
    }
}
