import SwiftUI
import AppKit

struct MainView: View {
    @ObservedObject private var appUpdates = AppUpdateService.shared
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var clashViewModel: ClashViewModel
    @EnvironmentObject private var clashController: ClashController
    @Environment(\.openWindow) private var openWindow

    private var destinations: [WorkspaceDestination] {
        DSSidebarSection.all.flatMap { section in
            section.items.map { item in
                WorkspaceDestination(id: item.displayName, title: item.displayName, icon: item.sidebarIcon, section: section.id)
            }
        }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            WorkspaceSidebar(
                destinations: destinations,
                selection: Binding(
                    get: { appState.selection.displayName },
                    set: { title in
                        let items = DSSidebarSection.all.flatMap(\.items)
                        if let item = items.first(where: { $0.displayName == title }) { appState.selection = item }
                    }
                )
            )
            .toolbar { AresSidebarToolbar(visibility: $columnVisibility) }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 250)
        } detail: {
            detail
                .frame(minWidth: 680, minHeight: 540)
                .background(DS.canvas)
                .navigationTitle([.applications, .quality, .policies, .scenes].contains(appState.selection) || appState.selection == .dashboard || appState.selection == .proxies || appState.selection == .rules || appState.selection == .logs || appState.selection == .subscriptions || appState.selection == .connections || appState.selection == .topology ? "" : appState.selection.displayName)
        }
        .toolbarBackground(.hidden, for: .windowToolbar)
        .background(SidebarToolbarAppearance())
        .background(WindowUpdateIndicator(version: appUpdates.availableVersion, action: appUpdates.checkForUpdates))
        .alert("Operation failed", isPresented: Binding(
            get: { appState.lastOperationError != nil },
            set: { if !$0 { appState.clearOperationError() } }
        )) {
            Button("OK") { appState.clearOperationError() }
        } message: {
            Text(appState.lastOperationError ?? "")
        }
        .tint(DS.accent)
        .onAppear { WindowAccessor.openWindow = openWindow }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch appState.selection {
        case .applications:
            ApplicationRoutingView(embedded: true)
                .toolbar { CollectionTitleToolbar(title: "Applications", count: nil, unit: "") }
        case .quality:
            ScrollView { NetworkQualityView(embedded: true).frame(maxWidth: .infinity) }
                .scrollIndicators(.never, axes: [.horizontal, .vertical])
                .toolbar { CollectionTitleToolbar(title: "Network Quality", count: nil, unit: "") }
        case .policies:
            PolicyGroupsView(embedded: true)
        case .scenes:
            ScenariosView(embedded: true)
                .scrollIndicators(.never, axes: [.horizontal, .vertical])
                .toolbar { CollectionTitleToolbar(title: "Scenes", count: nil, unit: "") }
        case .dashboard:
            DashboardView()
        case .proxies:
            ProxiesView()
        case .rules:
            RulesView()
        case .subscriptions:
            ProfilesView()
        case .connections:
            ActivityWorkspaceView()
        case .topology:
            ActivityWorkspaceView()
        case .analysis:
            AnalysisView()
        case .logs:
            LogsView()
        case .settings:
            SettingsView()
        }
    }
}

// MARK: - Mode label

extension ClashConfig.Mode {
    var displayLabel: String {
        switch self {
        case .rule: return "Rule mode"
        case .global: return "Global mode"
        case .direct: return "Direct mode"
        }
    }
}
