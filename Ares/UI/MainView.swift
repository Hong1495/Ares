import SwiftUI

struct MainView: View {
    @EnvironmentObject private var appState: AppState
    
    var body: some View {
        NavigationSplitView {
            List(selection: $appState.selection) {
                NavigationLink(value: AppState.NavigationItem.dashboard) {
                    Label("Dashboard", systemImage: "gauge.with.dots.needle.bottom.50percent")
                }
                NavigationLink(value: AppState.NavigationItem.proxies) {
                    Label("Proxies", systemImage: "network")
                }
                NavigationLink(value: AppState.NavigationItem.profiles) {
                    Label("Profiles", systemImage: "doc.text.fill")
                }
                NavigationLink(value: AppState.NavigationItem.connections) {
                    Label("Connections", systemImage: "point.3.connected.trianglepath.dotted")
                }
                NavigationLink(value: AppState.NavigationItem.antigravity) {
                    Label("Antigravity", systemImage: "sparkles")
                }
                NavigationLink(value: AppState.NavigationItem.logs) {
                    Label("Logs", systemImage: "list.bullet.rectangle.portrait")
                }
                NavigationLink(value: AppState.NavigationItem.settings) {
                    Label("Settings", systemImage: "gearshape")
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Ares")
        } detail: {
            switch appState.selection {
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
            }
        }
    }
}
