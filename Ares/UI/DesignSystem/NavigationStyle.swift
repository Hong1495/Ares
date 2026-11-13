import SwiftUI

// MARK: - Sidebar model

extension AppState.NavigationItem {
    var sidebarIcon: String {
        switch self {
        case .applications: return "app.connected.to.app.below.fill"
        case .quality: return "waveform.path.ecg"
        case .policies: return "slider.horizontal.3"
        case .scenes: return "square.stack.3d.up"
        case .dashboard: return "gauge.with.dots.needle.50percent"
        case .connections: return "arrow.up.arrow.down"
        case .proxies: return "network"
        case .rules: return "list.bullet.indent"
        case .subscriptions: return "rectangle.stack"
        case .topology: return "point.3.connected.trianglepath.dotted"
        case .analysis: return "waveform.path.ecg.rectangle"
        case .logs: return "text.alignleft"
        case .settings: return "gearshape"
        }
    }
}

struct DSSidebarSection: Identifiable {
    let id: String
    let items: [AppState.NavigationItem]

    static let all: [DSSidebarSection] = [
        .init(id: "Overview", items: [.dashboard, .connections, .quality]),
        .init(id: "Routing", items: [.proxies, .applications, .policies, .rules, .scenes]),
        .init(id: "Library", items: [.subscriptions]),
        .init(id: "Tools", items: [.analysis, .logs]),
        .init(id: "Preferences", items: [.settings])
    ]
}
