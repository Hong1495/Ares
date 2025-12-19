import Foundation
import ServiceManagement

/// Service to manage "Start at Login" functionality
class LaunchService {
    static let shared = LaunchService()
    
    private init() {}
    
    /// Check if app is currently in login items
    func isEnabled() -> Bool {
        return SMAppService.mainApp.status == .enabled
    }
    
    /// Enable or disable start at login
    func setLaunchAtLogin(enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
