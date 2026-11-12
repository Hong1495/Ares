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
    @State private var page = "Activity"
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
        WorkspaceDestination(id: "Activity", title: "Activity", icon: "arrow.up.arrow.down", section: "Monitoring"),
        WorkspaceDestination(id: "Proxies", title: "Proxies", icon: "network", section: "Proxy"),
        WorkspaceDestination(id: "Rules", title: "Rules", icon: "list.bullet.indent", section: "Proxy"),
        WorkspaceDestination(id: "Subscriptions", title: "Subscriptions", icon: "rectangle.stack", section: "Proxy"),
        WorkspaceDestination(id: "Routing", title: "Routing", icon: "globe.americas", section: "Explore"),
        WorkspaceDestination(id: "Analysis", title: "Analysis", icon: "waveform.path.ecg.rectangle", section: "Developer"),
        WorkspaceDestination(id: "Logs", title: "Logs", icon: "text.alignleft", section: "Developer"),
        WorkspaceDestination(id: "Dashboard", title: "Dashboard", icon: "gauge.with.dots.needle.50percent", section: "Preferences"),
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
                if page == "Dashboard" { dashboard } else { secondaryPage }
            }
            .frame(minWidth: 650, minHeight: 540)
            .background(DS.canvas)
            .navigationTitle(page == "Activity" ? "" : page)
            .toolbar {
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
        DashboardComposition(runtime: error ? "Core unavailable" : (enabled ? "Running" : "Stopped"), version: "Mihomo 1.19 · Sample", status: error ? .critical : (enabled ? .good : .idle), api: "HTTP :7890 · SOCKS :7891 · API :9090") {
            OverviewTrafficCard(points: points, download: snapshot.download, upload: snapshot.upload)
        } controls: {
            OverviewConnectionCard(snapshot: snapshot, systemProxy: $enabled, tun: $tun, interception: $inspection, mode: $mode)
        } details: {
            DSCard(padding: 0) {
                DSCardHeader("Proxy", icon: "server.rack") {
                    Button { measured.toggle() } label: { Image(systemName: "bolt.horizontal") }.buttonStyle(.borderless).help("Measure latency")
                }
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mode == 2 ? "Direct connection" : (empty ? "No active proxy" : selectedNode)).font(DS.Typography.body.weight(.semibold))
                        if mode != 2 { Text("Automatic selection").font(DS.Typography.metadata).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    if mode != 2 {
                        HStack(alignment: .lastTextBaseline, spacing: 2) {
                            Text(empty ? "—" : (measured ? "42" : "38")).font(DS.Typography.metric).foregroundStyle(Color.statusGood)
                            Text("ms").font(DS.Typography.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            DSCard(padding: 0) {
                DSCardHeader("IP address", icon: "globe.americas") {
                    Button { measured.toggle() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless).help("Refresh public IP")
                }
                HStack {
                    Text(empty ? "—" : "203.0.113.24").font(DS.Typography.title.monospaced().weight(.semibold))
                    if !empty { DSTag(text: "JP", tint: .secondary) }
                }
                DSKeyValueRow(label: "Local", value: "192.0.2.10 · Wi-Fi")
            }
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
        } advanced: {
            DSCard(padding: 0, spacing: DS.Space.sm) {
                DSCardHeader("Personal", icon: "creditcard") {
                    Button { measured.toggle() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless).help("Refresh subscription")
                }
                if empty {
                    Text("No subscription").font(DS.Typography.secondary).foregroundStyle(.secondary)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("28.4 GB").font(DS.Typography.title.weight(.semibold))
                        Text("of 200 GB").foregroundStyle(.secondary)
                        Spacer()
                        Text("14%").foregroundStyle(.secondary)
                    }.font(DS.Typography.metadata)
                    ProgressView(value: 0.142).tint(DS.accent)
                    Text("Expires Dec 31, 2026").font(DS.Typography.metadata).foregroundStyle(.secondary)
                }
            }
            DSCard(padding: 0, spacing: DS.Space.sm) {
                DSCardHeader("DNS", icon: "network.badge.shield.half.filled")
                ForEach(["223.5.5.5", "119.29.29.29"], id: \.self) { server in
                    Text(server).font(DS.Typography.secondary.monospaced().weight(.medium))
                }
            }
            DSCard(padding: 0, spacing: DS.Space.sm) {
                DSCardHeader("Bypass", icon: "arrow.triangle.turn.up.right.diamond")
                Text("localhost · 127.* · 10.*\n172.16.* · 172.31.* · 192.168.*")
                    .font(DS.Typography.metadata.monospaced()).foregroundStyle(.secondary).lineSpacing(6)
            }
            diagnostic("MITM", icon: "eye", rows: [("Certificate", "Not installed"), ("Ports", "80, 443, 8080, 8443"), ("Scope", "All hosts")])
            diagnostic("Core", icon: "cpu", rows: [("Latest release", "1.19"), ("API", error ? "Unreachable" : "Reachable")])
            DSCard(padding: 0, spacing: DS.Space.sm) {
                DSCardHeader("System", icon: "desktopcomputer")
                Text("macOS 27.2.1 · arm64").font(DS.Typography.secondary)
                Text("32 GB memory").font(DS.Typography.metadata).foregroundStyle(.secondary).help("Physical memory")
            }
        }
    }

    private func diagnostic(_ title: String, icon: String, rows: [(String, String)]) -> some View {
        DSCard(padding: 0, spacing: DS.Space.sm) {
            DSCardHeader(title, icon: icon)
            ForEach(rows.indices, id: \.self) { index in
                DSKeyValueRow(label: rows[index].0, value: rows[index].1)
            }
        }
    }

    private var secondaryPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            if ["Proxies", "Rules", "Subscriptions"].contains(page) {
                proxyPage
            } else if page == "Settings" {
                DSPageTabs(titles: ["General", "Network", "TUN", "MITM", "Rules"], selection: $tab)
                settingsPage
            } else if page == "Activity" {
                if tab == 0 {
                    ContentUnavailableView("No active connections", systemImage: "point.3.connected.trianglepath.dotted", description: Text("Applications and their connections appear here."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else { activityPage }
            } else if page == "Routing" {
                ContentUnavailableView("No active routes", systemImage: "point.3.connected.trianglepath.dotted", description: Text("Route activity appears here while connections are open."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(DSSurfaceBackground())
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
        case "Routing": return "A wider view of where your traffic travels."
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

    private var settingsPage: some View {
        ScrollView {
            VStack(spacing: 20) {
                DSCard(padding: 24, spacing: 24) {
                    DSCardHeader(["Startup & Appearance", "Traffic", "Interface", "Interception", "Custom routing"][tab], icon: "slider.horizontal.3")
                    DSToggleRow(icon: "power", title: ["Start with macOS", "Allow LAN", "Auto route", "Enable inspection", "Custom rules"][tab], isOn: $autoScroll)
                    Divider().opacity(0.5)
                    HStack {
                        Text(tab == 0 ? "Theme" : "Mode").font(DS.Typography.secondary)
                        Spacer()
                        Picker("Theme", selection: $theme) { Text("System").tag(0); Text("Light").tag(1); Text("Dark").tag(2) }.labelsHidden().frame(width: 150)
                            .onChange(of: theme) { _, value in dark = value == 2 }
                    }
                    DSKeyValueRow(label: "Configuration", value: "Preview session only")
                }
                DSCard(padding: 24, spacing: 20) {
                    DSCardHeader("About this preview", icon: "info.circle")
                    Text("Shared Ares presentation components with sample data. Controls affect this preview only.")
                        .font(DS.Typography.secondary).foregroundStyle(.secondary)
                }
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
