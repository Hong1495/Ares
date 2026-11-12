import Foundation

enum GroupingMode: String, CaseIterable, Identifiable {
    case app = "Application"
    case proxy = "Proxy Node"
    case host = "Host / Domain"
    case rule = "Rule"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .app: return "app"
        case .proxy: return "network"
        case .host: return "globe"
        case .rule: return "list.bullet.rectangle"
        }
    }
}

