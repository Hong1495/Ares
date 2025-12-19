import Foundation

/// App-level configuration and preferences
struct AresConfig: Codable {
    // UI Settings
    var theme: Theme = .system
    var language: String = Locale.current.language.languageCode?.identifier ?? "en"
    
    // System Integration
    var enableSystemProxy: Bool = false
    var enableTunMode: Bool = false
    var autoLaunch: Bool = false
    var silentStart: Bool = false
    
    // Proxy Settings
    var proxyHost: String = "127.0.0.1"
    
    enum Theme: String, Codable {
        case light
        case dark
        case system
    }
}
