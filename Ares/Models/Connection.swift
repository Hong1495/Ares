import Foundation

/// Connection model
nonisolated struct Connection: Identifiable, Sendable, Hashable {
    let id: String
    var metadata: ConnectionMetadata
    let upload: Int64
    let download: Int64
    let start: Date
    let chains: [String]
    let rule: String
    let rulePayload: String
    
    // Calculated fields for UI
    var uploadSpeed: Int64 = 0
    var downloadSpeed: Int64 = 0
    
    var duration: TimeInterval {
        Date().timeIntervalSince(start)
    }
    
    // Sorting helpers
    var chainsString: String { chains.joined(separator: " / ") }
    var identity: ConnectionIdentity { ConnectionIdentity(path: metadata.processPath, process: metadata.process, source: metadata.sourceIP) }
    var processName: String { identity.name }
    var sourceString: String { "\(metadata.sourceIP):\(metadata.sourcePort)" }
    var destinationString: String { "\(metadata.destinationIP):\(metadata.destinationPort)" }
    var typeString: String { "\(metadata.network.uppercased())(\(metadata.type.lowercased()))" }
    
    static func == (lhs: Connection, rhs: Connection) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

nonisolated struct ConnectionMetadata: Codable, Sendable {
    let network: String
    let type: String
    let sourceIP: String
    let destinationIP: String
    let sourcePort: String
    let destinationPort: String
    let host: String
    var processPath: String?
    var process: String? = nil
    var inboundName: String? = nil
    var inboundIP: String? = nil
    var inboundPort: String? = nil
   
    enum CodingKeys: String, CodingKey {
        case network, type
        case sourceIP = "sourceIP"
        case destinationIP = "destinationIP"
        case sourcePort = "sourcePort"
        case destinationPort = "destinationPort"
        case host
        case processPath, process, inboundName, inboundIP, inboundPort
    }
}
