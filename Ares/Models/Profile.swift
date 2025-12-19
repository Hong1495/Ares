import Foundation

/// Profile types supported by Ares
enum ProfileType: String, Codable {
    case remote  // Remote subscription URL
    case local   // Local YAML file
}

/// Profile model representing a Clash configuration profile
struct Profile: Identifiable, Codable {
    /// Unique identifier
    let id: UUID
    
    /// Display name
    var name: String
    
    /// Profile type (remote or local)
    var type: ProfileType
    
    /// Remote URL (for remote profiles)
    var url: URL?
    
    /// Local file path
    var path: URL?
    
    /// Update interval in seconds (default: 7 days for remote profiles)
    var updateInterval: TimeInterval = 86400 * 7
    
    /// Last update timestamp
    var lastUpdated: Date?
    
    /// Initialize a new remote profile
    static func remote(name: String, url: URL) -> Profile {
        Profile(
            id: UUID(),
            name: name,
            type: .remote,
            url: url,
            path: nil,
            lastUpdated: nil
        )
    }
    
    /// Initialize a new local profile
    static func local(name: String, path: URL) -> Profile {
        Profile(
            id: UUID(),
            name: name,
            type: .local,
            url: nil,
            path: path,
            lastUpdated: Date()
        )
    }
}
