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
                // 1. Dashboard
                NavigationLink(value: AppState.NavigationItem.dashboard) {
                    Label {
                        Text("Dashboard")
                    } icon: {
                        Image(systemName: "square.grid.2x2")
                            .imageScale(.medium)
                            .fontWeight(.light)
                            .frame(width: 20)
                    }
                }
                
                // 2. Activity (Connections) - Moved here per user request
                NavigationLink(value: AppState.NavigationItem.connections) {
                    Label {
                        Text("Activity") // Renamed from Connections
                    } icon: {
                        // Use a chart icon to represent activity
                        Image(systemName: "arrow.up.arrow.down")
                            .imageScale(.medium)
                            .fontWeight(.light)
                            .frame(width: 20)
                    }
                }
                
                // 3. Proxies
                NavigationLink(value: AppState.NavigationItem.proxies) {
                    Label {
                        Text("Proxies")
                    } icon: {
                        Image(systemName: "server.rack")
                            .imageScale(.medium)
                            .fontWeight(.light)
                            .frame(width: 20)
                    }
                }
                
                // 4. Rules
                NavigationLink(value: AppState.NavigationItem.rules) {
                    Label {
                        Text("Rules")
                    } icon: {
                        Image(systemName: "shield")
                            .imageScale(.medium)
                            .fontWeight(.light)
                            .frame(width: 20)
                    }
                }
                
                // 5. Profiles
                NavigationLink(value: AppState.NavigationItem.profiles) {
                    Label {
                        Text("Profiles")
                    } icon: {
                        Image(systemName: "rectangle.stack")
                            .imageScale(.medium)
                            .fontWeight(.light)
                            .frame(width: 20)
                    }
                }
                
                // 6. Analysis
                NavigationLink(value: AppState.NavigationItem.analysis) {
                    Label {
                        Text("Analysis")
                    } icon: {
                        Image(systemName: "chart.bar")
                            .imageScale(.medium)
                            .fontWeight(.light)
                            .frame(width: 20)
                    }
                }

                // 7. Logs
                NavigationLink(value: AppState.NavigationItem.logs) {
                    Label {
                        Text("Logs")
                    } icon: {
                        Image(systemName: "terminal")
                            .imageScale(.medium)
                            .fontWeight(.light)
                            .frame(width: 20)
                    }
                }
                
                // 8. Settings
                NavigationLink(value: AppState.NavigationItem.settings) {
                    Label {
                        Text("Settings")
                    } icon: {
                        Image(systemName: "gear")
                            .imageScale(.medium)
                            .fontWeight(.light)
                            .frame(width: 20)
                    }
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
            case .rules:
                RulesView()
            case .settings:
                SettingsView()
            }
        }
    }
}
