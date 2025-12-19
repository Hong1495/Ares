import SwiftUI

struct MainView: View {
    @State private var selection: NavigationItem? = .dashboard
    
    enum NavigationItem: Hashable {
        case dashboard
        case proxies
        case profiles
        case connections
        case logs
        case antigravity
        case rules
        case settings
    }
    
    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                NavigationLink(value: NavigationItem.dashboard) {
                    Label("Dashboard", systemImage: "gauge.with.dots.needle.bottom.50percent")
                }
                NavigationLink(value: NavigationItem.proxies) {
                    Label("Proxies", systemImage: "network")
                }
                NavigationLink(value: NavigationItem.profiles) {
                    Label("Profiles", systemImage: "doc.text.fill")
                }
                NavigationLink(value: NavigationItem.connections) {
                    Label("Connections", systemImage: "point.3.connected.trianglepath.dotted")
                }
                NavigationLink(value: NavigationItem.antigravity) {
                    Label("Antigravity", systemImage: "sparkles")
                }
                NavigationLink(value: NavigationItem.logs) {
                    Label("Logs", systemImage: "list.bullet.rectangle.portrait")
                }
                NavigationLink(value: NavigationItem.settings) {
                    Label("Settings", systemImage: "gearshape")
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Ares")
        } detail: {
            switch selection {
            case .dashboard:
                DashboardView()
            case .proxies:
                ProxiesView()
            case .profiles:
                ProfilesView()
            case .connections:
                ConnectionsView()
            case .logs:
                LogsView()
            case .antigravity:
                AntigravityView()
            case .rules:
                Text("Rules - Coming Soon")
            case .settings:
                SettingsView()
            case .none:
                Text("Select an item")
            }
        }
    }
}
