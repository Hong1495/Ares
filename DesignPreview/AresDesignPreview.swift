import SwiftUI
import AppKit

// No production delegate, services, models, storage, timers, or network clients.
// Every control in this executable changes only local @State.
@main
struct AresDesignPreview: App {
    var body: some Scene {
        WindowGroup("Ares · Design Preview") {
            if CommandLine.arguments.contains("--menu-preview") {
                MenuBarPreview().preferredColorScheme(.dark)
            } else {
                PreviewWorkspace().frame(minWidth: 900, minHeight: 650)
            }
        }
        .defaultSize(width: CommandLine.arguments.contains("--compact") ? 905 : 1180, height: 900)
        .windowStyle(.titleBar)
        .commands { PreviewCommands() }
        MenuBarExtra(isInserted: .constant(!CommandLine.arguments.contains("--menu-preview"))) {
            MenuBarPreview()
        } label: {
            AresMenuBarLabel(showsLatency: true, latency: 639)
        }.menuBarExtraStyle(.window)
    }
}

struct PreviewWorkspace: View {
    @State private var showUpdate = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var page = CommandLine.arguments.first(where: { $0.hasPrefix("--page=") }).map { String($0.dropFirst(7)) } ?? (CommandLine.arguments.contains("--settings-sources") ? "Settings" : "Dashboard")
    @State private var dark = CommandLine.arguments.contains("--dark")
    @State private var enabled = true
    @State private var tun = false
    @State private var inspection = false
    @State private var mode = 0
    @State private var tab = 0
    @State private var activityGrouping = "Application"
    @State private var selectedNode = "🇹🇼 台湾🚀 · 01"
    @State private var previewGroup: String? = "Select"
    @State private var previewFocus: String?
    @State private var search = ""
    @State private var measured = false
    @State private var empty = CommandLine.arguments.contains("--empty")
    @State private var error = CommandLine.arguments.contains("--unavailable")
    @State private var autoScroll = true
    @State private var theme = 0

    private let destinations = [
        WorkspaceDestination(id: "Dashboard", title: "Dashboard", icon: WorkspaceSymbols.dashboard, section: "Overview"),
        WorkspaceDestination(id: "Activity", title: "Activity", icon: "arrow.up.arrow.down", section: "Overview"),
        WorkspaceDestination(id: "Quality", title: "Quality", icon: "waveform.path.ecg", section: "Overview"),
        WorkspaceDestination(id: "Proxies", title: "Proxies", icon: "network", section: "Routing"),
        WorkspaceDestination(id: "Applications", title: "Applications", icon: "app.connected.to.app.below.fill", section: "Routing"),
        WorkspaceDestination(id: "Devices", title: "Devices", icon: "laptopcomputer.and.iphone", section: "Routing"),
        WorkspaceDestination(id: "Policies", title: "Policies", icon: "slider.horizontal.3", section: "Routing"),
        WorkspaceDestination(id: "Rules", title: "Rules", icon: "list.bullet.indent", section: "Routing"),
        WorkspaceDestination(id: "Scenes", title: "Scenes", icon: "square.stack.3d.up", section: "Routing"),
        WorkspaceDestination(id: "Subscriptions", title: "Subscriptions", icon: "rectangle.stack", section: "Library"),
        WorkspaceDestination(id: "Resources", title: "Resources", icon: "shippingbox", section: "Library"),
        WorkspaceDestination(id: "Analysis", title: "Analysis", icon: "waveform.path.ecg.rectangle", section: "Tools"),
        WorkspaceDestination(id: "Logs", title: "Logs", icon: "text.alignleft", section: "Tools"),
        WorkspaceDestination(id: "Settings", title: "Settings", icon: "slider.horizontal.3", section: "Preferences")
    ]

    private var snapshot: OverviewSnapshot {
        OverviewSnapshot(title: error ? "Connection needs attention" : (enabled ? "You're connected." : "Ready when you are."),
                         subtitle: enabled ? "System traffic is flowing through your selected route." : "Enable a connection to find your flow.",
                         status: error ? .critical : (enabled ? .good : .idle), runtime: error ? "Unavailable" : (enabled ? "Running" : "Stopped"),
                         node: empty ? "No node selected" : selectedNode, latency: empty ? nil : 38, connections: enabled ? 24 : 0,
                         download: enabled ? "4.82 MB/s" : "0 B/s", upload: enabled ? "236 KB/s" : "0 B/s")
    }

    private let previewNodes = ["🇹🇼 台湾🚀 · 01", "🇹🇼 台湾家宽 · 02", "🇯🇵 Tokyo · 01", "🇸🇬 Singapore · 01", "🇭🇰 Hong Kong · 01", "🇺🇸 Los Angeles · 01", "London · 01"]

    private var points: [OverviewTrafficPoint] {
        let start = Date().addingTimeInterval(-60)
        let gap = CommandLine.arguments.contains("--traffic-gap")
        return (0..<60).filter { !gap || !(20...28).contains($0) }.map { i in
            let wave = max(0, sin(Double(i) * 0.24) * 0.8 + sin(Double(i) * 0.71) * 0.22 + 1.1)
            return OverviewTrafficPoint(time: start.addingTimeInterval(Double(i)), download: enabled ? wave * 2_800_000 : 0, upload: enabled ? wave * 240_000 : 0,
                                        segment: gap && i > 28 ? 1 : 0)
        }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            WorkspaceSidebar(destinations: destinations, selection: $page)
            .toolbar { AresSidebarToolbar(visibility: $columnVisibility) }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
        } detail: {
            Group {
                if page == "Dashboard" { dashboard } else if page == "Logs" { LogsPreview(empty: empty) } else if page == "Settings" { SettingsPreview() } else { secondaryPage }
            }
            .frame(minWidth: 650, minHeight: 540)
            .background(DS.canvas)
            .navigationTitle(page == "Activity" || page == "Dashboard" || ["Proxies", "Rules", "Subscriptions", "Logs"].contains(page) ? "" : page)
            .toolbar {
                if page == "Dashboard" {
                    ToolbarItem(placement: .navigation) {
                        DashboardTitleSummary(country: empty ? nil : "JP", ip: empty ? "—" : "203.0.113.24", latency: empty || mode == 2 ? nil : 38, showsRisk: true, risk: empty || error ? nil : 33, riskHelp: "Preview · 33/100 risk · proxycheck.io").padding(.leading, 16)
                    }.aresUnframed()
                }
                if page == "Proxies" { ProxiesTitleToolbar(count: empty ? 0 : previewNodes.count) }
                if page == "Rules" { CollectionTitleToolbar(title: "Rules", count: empty ? 0 : 4, unit: "Rules") }
                if page == "Subscriptions" { CollectionTitleToolbar(title: "Subscriptions", count: empty ? 0 : 2, unit: "Profiles") }
                if page == "Activity" {
                    ActivityTitleToolbar(count: tab == 0 ? 9 : 13,
                                         topologySummary: tab == 0 ? "9 processes · 3 rule types · 2 routes · 18 targets" : nil,
                                         subtitle: tab == 0 ? "Topology" : "Connections",
                                         download: tab == 0 ? nil : "1.3 MB",
                                         upload: tab == 0 ? nil : "3.6 MB")
                    ToolbarItem(placement: .primaryAction) {
                        ActivityViewPicker(selection: $tab)
                    }.aresUnframed()
                }
            }
        }
        .aresWorkspaceChrome()
        .background(WindowUpdateIndicator(version: "1.1") { showUpdate = true })
        .alert("Ares 1.1 is available", isPresented: $showUpdate) {
            Button("Done", role: .cancel) { }
        } message: { Text("Preview only · Download and installation are disabled.") }
        .tint(DS.accent)
        .preferredColorScheme(dark ? .dark : .light)
        .focusedSceneValue(\.previewOptions, PreviewOptions(empty: $empty, error: $error, dark: $dark))
        .onChange(of: page) { _, _ in tab = 0; search = "" }
    }

    private var dashboard: some View {
        DashboardComposition {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                OverviewTrafficCard(points: points, download: snapshot.download, upload: snapshot.upload)
            }
        } controls: {
            OverviewConnectionCard(snapshot: snapshot, systemProxy: $enabled, tun: $tun, interception: $inspection, mode: $mode)
        } details: {
            OverviewWorkspaceSummary(
                probes: ["Google", "Cloudflare", "GitHub", "DNS"].map { .init(id: $0, name: $0, success: "83.3%", latency: 42, samples: [30, 44, 36, nil, 50, 42]) },
                configuration: .init(
                    resources: error ? nil : .init(nodes: empty ? 0 : 32, providers: empty ? 0 : 8, local: empty ? 0 : 12),
                    devices: .init(enabled: empty ? 0 : 2, disabled: empty ? 0 : 1, live: error ? nil : .init(active: empty ? 0 : 1, connections: empty ? 0 : 4)),
                    applications: empty ? [] : [.init(application: "Safari", target: "Automatic"), .init(application: "Mail", target: "DIRECT"), .init(application: "Notion Helper", target: "节点选择"), .init(application: "Editor", target: "Work")],
                    policies: empty ? [:] : ["select": 4, "url-test": 2, "fallback": 1, "load-balance": 1],
                    scenes: .init(names: empty ? [] : ["Home", "Office", "Travel"], automation: empty ? .off : .paused)),
                openResources: { page = "Resources" }, openDevices: { page = "Devices" },
                processes: empty ? [] : [.init(id: "browser", name: "Safari", connections: 12), .init(id: "editor", name: "Code Editor", connections: 8), .init(id: "mail", name: "Mail", connections: 4), .init(id: "music", name: "Music", connections: 2), .init(id: "calendar", name: "Calendar", connections: 1), .init(id: "sync", name: "Sync", connections: 1)],
                activityStatus: empty ? "No active connections" : "All sources · Ares excluded",
                connections: empty ? 0 : 28, processCount: empty ? 0 : 6,
                qualityStatus: "Preview · 6 samples", qualityGroup: "Ares Auto",
                route: "Ares Route → Ares Auto → Japan",
                openActivity: { page = "Activity" }, openApplications: { page = "Applications" }, openQuality: { page = "Quality" }, openPolicies: { page = "Policies" }, openScenes: { page = "Scenes" })

        }
    }

    @ViewBuilder private var secondaryPage: some View {
        if page == "Rules" || page == "Subscriptions" {
            CollectionPreview(subscriptions: page == "Subscriptions", empty: empty).id(page)
        } else {
        VStack(alignment: .leading, spacing: 22) {
            if ["Proxies", "Rules", "Subscriptions"].contains(page) {
                proxyPage

            } else if page == "Activity" {
                if tab == 0 {
                    ContentUnavailableView("No active connections", systemImage: "point.3.connected.trianglepath.dotted", description: Text("Applications and their connections appear here."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else { activityPage }
            } else {
                activityPage
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 30)
        .padding(.bottom, 30)
        .padding(.top, DS.Space.pageTop)
    }
    }

    private var subtitle: String {
        switch page {
        case "Proxy & Rules": return "Choose a path. Let everything else flow."
        case "Activity": return "Every connection, with a little more clarity."
        case "Settings": return "Make Ares feel at home on your Mac."
        case "Logs": return "A quiet record of what happens along the way."
        case "Topology": return "Follow the connections between apps and destinations."
        default: return "Look closer at the requests behind each connection."
        }
    }

    private func previewDelay(_ name: String) -> Int? {
        measured ? 42 : (name.contains("Singapore") ? 288 : name.contains("London") ? 817 : 38)
    }

    @ViewBuilder private var proxyPage: some View {
        if page == "Proxies" {
            WorkspaceControls(placeholder: mode == 2 ? nil : "Search nodes", search: $search) {
                Picker("Mode", selection: $mode) {
                    Text("Rule").tag(0)
                    Text("Global").tag(1)
                    Text("Direct").tag(2)
                }.pickerStyle(.segmented).labelsHidden()
            } actions: {
                if mode != 2 {
                    WorkspaceAction(title: "Test Latency", symbol: "bolt", primary: true) { measured.toggle() }
                    Menu {
                        Button("Refresh Nodes") { measured = false }
                        Button("Open Policies") { page = "Policies" }
                        Button("Open Node Providers") { page = "Resources" }
                    } label: { Image(systemName: "ellipsis.circle") }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("Proxy actions")
                }
            }
            if mode == 2 {
                ContentUnavailableView("Direct Connection", systemImage: "arrow.turn.up.right")
            } else if empty {
                ContentUnavailableView("No proxy groups", systemImage: "network.slash", description: Text("Add a subscription to get started."))
            } else {
                ProxyWorkspaceTable(
                    groups: [.init(id: "Select", type: "Selector", current: selectedNode, count: previewNodes.count)],
                    selectedGroup: $previewGroup, focusedNode: $previewFocus,
                    rows: ProxyNodeOrder.sorted(previewNodes.filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) }, delay: previewDelay).map {
                        .init(id: $0, type: "VLESS", delay: previewDelay($0), selected: $0 == selectedNode, active: $0 == selectedNode)
                    }, search: search, onSelect: { selectedNode = $0 }, onTest: { _ in measured.toggle() }, onResume: {}
                ).frame(minHeight: 360)
            }
        } else if page == "Rules" {
            DSCard {
                DSCardHeader("Routing rules", icon: "list.bullet.indent")
                ForEach(["DOMAIN-SUFFIX · apple.com", "DOMAIN-SUFFIX · github.com", "GEOIP · LAN", "MATCH"], id: \.self) { rule in
                    DSKeyValueRow(label: rule, value: "Automatic").padding(.vertical, 9)
                }
            }
        } else {
            DSCard {
                DSCardHeader("Personal subscription", icon: "rectangle.stack") { DSStatusPill(text: "Active", status: .good) }
                DSKeyValueRow(label: "Nodes", value: "12")
                DSKeyValueRow(label: "Usage", value: "28.4 GB / 200 GB")
                ProgressView(value: 0.142).tint(DS.accent)
            }
        }
    }

    private var activityPage: some View {
        VStack(spacing: 18) {
            if page == "Activity" {
                Picker("Group connections by", selection: $activityGrouping) {
                    ForEach(["Application", "Proxy Node", "Host / Domain", "Rule"], id: \.self) { title in
                        Text(title).tag(title)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            HStack {
                TextField(page == "Logs" ? "Search logs" : "Search connections", text: $search).textFieldStyle(.roundedBorder).frame(width: 250)
                Spacer()
                Toggle("Auto-scroll", isOn: $autoScroll).toggleStyle(.switch).controlSize(.mini).font(DS.Typography.metadata)
            }
            DSCard(padding: 20, spacing: 0) {
                if empty {
                    ContentUnavailableView("Nothing here yet", systemImage: "tray", description: Text("New activity will appear here."))
                        .frame(maxWidth: .infinity, minHeight: 280)
                } else {
                    ForEach(["api.github.com", "developer.apple.com", "cdn.example.com", "docs.swift.org"].filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) }, id: \.self) { host in
                        HStack(spacing: 16) {
                            Image(systemName: page == "Logs" ? "text.alignleft" : "globe").foregroundStyle(.secondary)
                            Text(page == "Logs" ? "[info] Connection established · \(host)" : host).font(DS.Typography.secondary.monospaced())
                            Spacer()
                            DSTag(text: "TCP", tint: DS.accent)
                            Text("38 ms").font(DS.Typography.metadata.monospaced()).foregroundStyle(.secondary)
                        }.padding(.vertical, 17)
                        Divider().opacity(0.4)
                    }
                }
            }
        }
    }
}

// Fixture controls live in the macOS menu bar, outside the product toolbar.
private struct PreviewOptions {
    var empty: Binding<Bool>
    var error: Binding<Bool>
    var dark: Binding<Bool>
}

private struct PreviewOptionsKey: FocusedValueKey {
    typealias Value = PreviewOptions
}

private extension FocusedValues {
    var previewOptions: PreviewOptions? {
        get { self[PreviewOptionsKey.self] }
        set { self[PreviewOptionsKey.self] = newValue }
    }
}

private struct PreviewCommands: Commands {
    @FocusedValue(\.previewOptions) private var options

    var body: some Commands {
        CommandMenu("Preview") {
            if let options {
                Toggle("Empty state", isOn: options.empty)
                Toggle("Error state", isOn: options.error)
                Toggle("Dark appearance", isOn: options.dark)
            }
        }
    }
}
