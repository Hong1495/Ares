import SwiftUI

struct MainView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(
                get: { appState.selection },
                set: { newValue in
                    if let val = newValue {
                        appState.selection = val
                    }
                }
            )) {
                // Group 1: General (No Header)
                Section {
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
                }

                // Group 2: Proxy
                Section("Proxy") {
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
                }

                // Group 3: Visualization
                Section("Visualization") {
                    NavigationLink(value: AppState.NavigationItem.topology) {
                        Label("Topology", systemImage: "arrow.triangle.pull")
                    }
                    NavigationLink(value: AppState.NavigationItem.routeMap) {
                        Label("Routing", systemImage: "map")
                    }
                }

                // Group 4: DevTools
                Section("DevTools") {
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
                }

                // Group 5: Config
                Section("Config") {
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
            case .topology:
                TopologyPageView()
            case .routeMap:
                RouteMapPageView()
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
