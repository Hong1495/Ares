import Foundation

/// Canonical column labels shared by the graph and its counters.
nonisolated struct TopologyRow: Equatable {
    let source: String
    let rule: String
    let proxy: String
    let target: String

    init(source: String, rule: String, chain: [String], host: String, destinationIP: String) {
        self.source = source.isEmpty ? "Unknown" : source
        self.rule = rule.isEmpty ? "Unknown" : rule
        target = host.isEmpty ? (destinationIP.isEmpty ? "Unknown" : destinationIP) : host
        proxy = chain.last(where: { $0 != "DIRECT" && $0 != host }) ?? "DIRECT"
    }
}

nonisolated struct TopologySnapshot: Equatable {
    let rows: [TopologyRow]
    let totalConnections: Int

    init(rows: [TopologyRow]) {
        totalConnections = rows.count
        self.rows = rows
    }

    var processCount: Int { Set(rows.map(\.source)).count }
    var ruleCount: Int { Set(rows.map(\.rule)).count }
    var proxyCount: Int { Set(rows.map(\.proxy)).count }
    var targetCount: Int { Set(rows.map(\.target)).count }
    var maximumColumnCount: Int { max(processCount, ruleCount, proxyCount, targetCount) }
    var summary: String {
        "\(processCount) processes · \(ruleCount) rule types · \(proxyCount) routes · \(targetCount) targets"
    }
    var subtitle: String {
        "Topology"
    }
}
