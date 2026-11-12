import SwiftUI

// MARK: - Sidebar model

extension AppState.NavigationItem {
    var sidebarIcon: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.50percent"
        case .connections: return "arrow.up.arrow.down"
        case .proxies: return "network"
        case .rules: return "list.bullet.indent"
        case .subscriptions: return "rectangle.stack"
        case .topology: return "point.3.connected.trianglepath.dotted"
        case .routeMap: return "globe.americas"
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
        .init(id: "Monitoring", items: [.connections]),
        .init(id: "Proxy", items: [.proxies, .rules, .subscriptions]),
        .init(id: "Explore", items: [.routeMap]),
        .init(id: "Developer", items: [.analysis, .logs]),
        .init(id: "Preferences", items: [.dashboard, .settings])
    ]
}
