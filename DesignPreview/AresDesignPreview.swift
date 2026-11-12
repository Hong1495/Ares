import SwiftUI
import AppKit

// No production delegate, services, models, storage, timers, or network clients.
// Every control in this executable changes only local @State.
@main
struct AresDesignPreview: App {
    var body: some Scene {
        WindowGroup("Ares · Design Preview") {
            PreviewWorkspace()
                .frame(minWidth: 900, minHeight: 650)
        }
        .defaultSize(width: 1180, height: 780)
        .windowStyle(.titleBar)
        .commands { PreviewCommands() }
        MenuBarExtra {
            Text("Ares preview · No network services")
        } label: {
            AresMenuBarLabel(showsLatency: true, latency: 639)
        }
    }
}

struct PreviewWorkspace: View {
    @State private var showUpdate = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var page = "Dashboard"
    @State private var dark = false
    @State private var enabled = true
    @State private var tun = false
    @State private var inspection = false
    @State private var mode = 0
    @State private var tab = 0
    @State private var activityGrouping = "Application"
    @State private var selectedNode = "Tokyo · 01"
    @State private var search = ""
    @State private var measured = false
    @State private var empty = false
    @State private var error = false
    @State private var autoScroll = true
    @State private var theme = 0

    private let destinations = [
        WorkspaceDestination(id: "Dashboard", title: "Dashboard", icon: "gauge.with.dots.needle.50percent", section: "Monitoring"),
        WorkspaceDestination(id: "Activity", title: "Activity", icon: "arrow.up.arrow.down", section: "Monitoring"),
        WorkspaceDestination(id: "Proxies", title: "Proxies", icon: "network", section: "Proxy"),
        WorkspaceDestination(id: "Rules", title: "Rules", icon: "list.bullet.indent", section: "Proxy"),
        WorkspaceDestination(id: "Subscriptions", title: "Subscriptions", icon: "rectangle.stack", section: "Proxy"),
        WorkspaceDestination(id: "Analysis", title: "Analysis", icon: "waveform.path.ecg.rectangle", section: "Developer"),
        WorkspaceDestination(id: "Logs", title: "Logs", icon: "text.alignleft", section: "Developer"),
        WorkspaceDestination(id: "Settings", title: "Settings", icon: "slider.horizontal.3", section: "Preferences")
    ]

    private var snapshot: OverviewSnapshot {
        OverviewSnapshot(title: error ? "Connection needs attention" : (enabled ? "You're connected." : "Ready when you are."),
                         subtitle: enabled ? "System traffic is flowing through your selected route." : "Enable a connection to find your flow.",
                         status: error ? .critical : (enabled ? .good : .idle), runtime: error ? "Unavailable" : (enabled ? "Running" : "Stopped"),
                         node: empty ? "No node selected" : selectedNode, latency: empty ? nil : 38, connections: enabled ? 24 : 0,
                         download: enabled ? "4.82 MB/s" : "0 B/s", upload: enabled ? "236 KB/s" : "0 B/s")
    }

    private var points: [OverviewTrafficPoint] {
        let start = Date().addingTimeInterval(-60)
        return (0..<60).map { i in
            let wave = max(0, sin(Double(i) * 0.24) * 0.8 + sin(Double(i) * 0.71) * 0.22 + 1.1)
            return OverviewTrafficPoint(id: i, time: start.addingTimeInterval(Double(i)), download: enabled ? wave * 2_800_000 : 0, upload: enabled ? wave * 240_000 : 0)
        }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            WorkspaceSidebar(destinations: destinations, selection: $page)
            .toolbar { AresSidebarToolbar(visibility: $columnVisibility) }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
        } detail: {
            Group {
                if page == "Dashboard" { dashboard } else if page == "Settings" { SettingsPreview() } else { secondaryPage }
            }
            .frame(minWidth: 650, minHeight: 540)
            .background(DS.canvas)
            .navigationTitle(page == "Activity" || page == "Dashboard" ? "" : page)
            .toolbar {
                if page == "Dashboard" {
                    ToolbarItem(placement: .navigation) {
                        DashboardTitleSummary(country: empty ? nil : "JP", ip: empty ? "—" : "203.0.113.24", latency: empty || mode == 2 ? nil : 38).padding(.leading, 16)
                    }.aresUnframed()
                }
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
        .toolbarBackground(.hidden, for: .windowToolbar)
        .background(SidebarToolbarAppearance())
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
            OverviewTrafficCard(points: points, download: snapshot.download, upload: snapshot.upload)
        } controls: {
            OverviewConnectionCard(snapshot: snapshot, systemProxy: $enabled, tun: $tun, interception: $inspection, mode: $mode)
        } details: {
            DSCard(padding: 0, spacing: DS.Space.sm) {
                DSCardHeader("Reachability", icon: "antenna.radiowaves.left.and.right") {
                    Button { measured.toggle() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless).help("Simulate measurement")
                }
                ForEach(["Google", "GitHub", "Gemini"], id: \.self) { name in
                    DSKeyValueRow(label: name, value: error ? "Unreachable" : (measured ? "42 ms" : "38 ms"), valueTint: error ? .statusBad : .secondary)
                        .padding(.vertical, 3)
                    if name != "Gemini" { Divider().opacity(0.35) }
                }
            }
        }
    }

    private var secondaryPage: some View {
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

    @ViewBuilder private var proxyPage: some View {
        if page == "Proxies" {
            HStack {
                TextField("Search nodes", text: $search).textFieldStyle(.roundedBorder).frame(width: 240)
                Spacer()
                Text("6 nodes").font(DS.Typography.metadata).foregroundStyle(.secondary)
            }
            if empty {
                ContentUnavailableView("No proxy groups", systemImage: "network.slash", description: Text("Add a subscription to get started."))
            } else {
                DSCard(padding: 22, spacing: 22) {
                    DSCardHeader("Automatic selection", icon: "hand.tap", subtitle: "Select a preferred route")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 195), spacing: 12)], spacing: 12) {
                        ForEach(["Tokyo · 01", "Tokyo · 02", "Singapore · 01", "Hong Kong · 01", "Los Angeles · 01", "London · 01"].filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) }, id: \.self) { name in
                            SimpleProxyButton(name: name, isSelected: name == selectedNode, delay: measured ? 42 : 38, isTesting: false, onSelect: { selectedNode = name }, onTest: { measured.toggle() })
                        }
                    }
                    if !search.isEmpty && !["Tokyo", "Singapore", "Hong Kong", "Los Angeles", "London"].contains(where: { $0.localizedCaseInsensitiveContains(search) }) {
                        Text("No nodes matching your search").font(DS.Typography.secondary).foregroundStyle(.secondary)
                    }
                }
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
