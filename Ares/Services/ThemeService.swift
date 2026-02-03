import SwiftUI
import Combine

/// Service to manage app theme (System, Light, Dark)
class ThemeService: ObservableObject {
    static let shared = ThemeService()
    
    private let defaults = UserDefaults.standard
    private let themeKey = DefaultsKeys.theme
    
    var theme: String {
        get { defaults.string(forKey: themeKey) ?? "system" }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: themeKey)
            applyTheme()
        }
    }
    
    private init() {
        applyTheme()
    }
    
    func applyTheme() {
        DispatchQueue.main.async {
            let theme = self.defaults.string(forKey: self.themeKey) ?? "system"
            switch theme {
            case "light":
                NSApp.appearance = NSAppearance(named: .aqua)
            case "dark":
                NSApp.appearance = NSAppearance(named: .darkAqua)
            default:
                NSApp.appearance = nil // System
            }
        }
    }
}
