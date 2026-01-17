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
                
                // 2. Activity (Connections)
                NavigationLink(value: AppState.NavigationItem.connections) {
                    Label {
                        Text("Activity")
                    } icon: {
                        Image(systemName: "arrow.up.arrow.down")
                            .imageScale(.medium)
                            .fontWeight(.light)
                            .frame(width: 20)
                    }
                }
                
                // 3. Policies (Combined Proxies & Rules)
                NavigationLink(value: AppState.NavigationItem.policies) {
                    Label {
                        Text("Policies")
                    } icon: {
                        Image(systemName: "hand.tap")
                            .imageScale(.medium)
                            .fontWeight(.light)
                            .frame(width: 20)
                    }
                }
                
                // 4. Analysis
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

                // 5. Logs
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
                
                // 6. Settings
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
            case .policies:
                PoliciesView()
            case .connections:
                ConnectionsView()
            case .analysis:
                AnalysisView()
            case .logs:
                LogsView()
            case .settings:
                SettingsView()
            }
        }
    }
}

