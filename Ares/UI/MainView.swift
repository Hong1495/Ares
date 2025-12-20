import SwiftUI

struct MainView: View {
    @EnvironmentObject private var appState: AppState
    
    var body: some View {
        NavigationSplitView {
            List(selection: Binding(
                get: { appState.selection },
                set: { newValue in
                    DispatchQueue.main.async {
                        if let val = newValue {
                            appState.selection = val
                        }
                    }
                }
            )) {
                NavigationLink(value: AppState.NavigationItem.dashboard) {
                    Label("Dashboard", systemImage: "gauge.with.dots.needle.bottom.50percent")
                        .font(.headline)
                }
                NavigationLink(value: AppState.NavigationItem.proxies) {
                    Label("Proxies", systemImage: "network")
                        .font(.headline)
                }
                NavigationLink(value: AppState.NavigationItem.rules) {
                    Label("Rules", systemImage: "checklist")
                        .font(.headline)
                }
                NavigationLink(value: AppState.NavigationItem.profiles) {
                    Label("Profiles", systemImage: "doc.text.fill")
                        .font(.headline)
                }
                NavigationLink(value: AppState.NavigationItem.connections) {
                    Label("Connections", systemImage: "point.3.connected.trianglepath.dotted")
                        .font(.headline)
                }
                NavigationLink(value: AppState.NavigationItem.analysis) {
                    Label("Analysis", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.headline)
                }
                NavigationLink(value: AppState.NavigationItem.antigravity) {
                    Label("Antigravity", systemImage: "sparkles")
                        .font(.headline)
                }
                NavigationLink(value: AppState.NavigationItem.logs) {
                    Label("Logs", systemImage: "list.bullet.rectangle.portrait")
                        .font(.headline)
                }
                NavigationLink(value: AppState.NavigationItem.settings) {
                    Label("Settings", systemImage: "gearshape")
                        .font(.headline)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle(appState.selection.displayName)
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
            case .analysis:
                AnalysisView()
            case .logs:
                LogsView()
            case .antigravity:
                AntigravityView()
            case .rules:
                RulesView()
            case .settings:
                SettingsView()
            }
        }
    }
}
