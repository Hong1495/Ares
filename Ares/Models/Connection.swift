import Foundation

/// Connection model
nonisolated struct Connection: Identifiable, Sendable, Hashable {
    let id: String
    let metadata: ConnectionMetadata
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
    var processName: String {
        guard let path = metadata.processPath, !path.isEmpty else { return "Unknown" }
        
        // Aggregate Helper Processes (Same logic as TrafficAuditManager)
        if path.contains(".app") {
            let components = path.split(separator: "/")
            var currentPath = ""
            for component in components {
                currentPath += "/" + component
                if component.hasSuffix(".app") {
                    return URL(fileURLWithPath: currentPath).deletingPathExtension().lastPathComponent
                }
            }
        }
        
        return URL(fileURLWithPath: path).lastPathComponent
    }
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
    let processPath: String?
   
    enum CodingKeys: String, CodingKey {
        case network, type
        case sourceIP = "sourceIP"
        case destinationIP = "destinationIP"
        case sourcePort = "sourcePort"
        case destinationPort = "destinationPort"
        case host
        case processPath
    }
}
