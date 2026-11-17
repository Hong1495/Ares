import SwiftUI
import Combine
import SubscriptionKit

enum ProxyTab: String, CaseIterable, Identifiable {
    case rule = "Rule"
    case global = "Global"
    case direct = "Direct"

    var id: String { rawValue }
}

struct ProxiesView: View {
    @EnvironmentObject var clashController: ClashController
    @EnvironmentObject var profileService: ProfileService
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var clashViewModel: ClashViewModel
    @State private var savedGroups: [ProxyGroup] = []
    @State private var savedNodes: [String: ProxyNode] = [:]
    @State private var providerCount = 0
    @State private var savedProfileKey = ""
    @State private var liveProfileKey = ""
    @State private var loadError: String?
    @State private var isLoading = false
    @State private var loadRevision = UUID()
    @State private var selectedTab: ProxyTab = .rule
    @State private var selectedGroup: String?
    @State private var focusedNode: String?
    @State private var searchText = ""
    @State private var showingResources = false
    private var profileKey: String { profileService.activeProfileRevision }

    private var showingLive: Bool {
        clashViewModel.isRunning && !clashViewModel.isToggling && clashViewModel.appliedProfileRevision == profileKey && liveProfileKey == profileKey && !liveProfileKey.isEmpty
    }
    private var displayGroups: [ProxyGroup] {
        if showingLive { return clashController.proxyGroups }
        return (savedProfileKey == profileKey ? savedGroups : []).map { group in
            var result = group
            if let node = profileService.savedNode(group: group.name), group.all.contains(node) {
                result.now = node
                if group.supportsAutomaticSelection { result.fixed = node }
            }
            return result
        }
    }
    private var displayNodes: [String: ProxyNode] {
        showingLive ? clashController.proxyNodes : (savedProfileKey == profileKey ? savedNodes : [:])
    }
    private var nodeCount: Int {
        let groupNames = Set(displayGroups.map(\.name))
        let builtIns = Set(["Direct", "Reject", "RejectDrop", "Pass", "Compatible", "PassRule"])
        return displayNodes.values.filter { !groupNames.contains($0.name) && !builtIns.contains($0.type) }.count
    }

    // Filter groups based on selected tab
    var filteredGroups: [ProxyGroup] {
        switch selectedTab {
        case .rule:
            let allGroups = displayGroups.filter { $0.name != "GLOBAL" }
            return allGroups.sorted { a, b in
                if (a.type == "Selector") != (b.type == "Selector") { return a.type == "Selector" }
                if a.name == "🚀 节点选择" { return true }
                if b.name == "🚀 节点选择" { return false }
                return a.name < b.name
            }
        case .global:
            if showingLive { return displayGroups.filter { $0.name == "GLOBAL" } }
            return displayNodes.isEmpty ? [] : [ProxyGroup(name: "GLOBAL", type: "Selector", now: profileService.savedNode(group: "GLOBAL"), all: displayNodes.keys.sorted())]
        case .direct:
            return []
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            Divider()

            content
        }
        .navigationTitle("")
        .toolbar { ProxiesTitleToolbar(count: nodeCount) }
        .sheet(isPresented: $showingResources) { ProxyResourcesView().environmentObject(clashController) }
        .onAppear { selectedTab = ProxyTab(rawValue: appState.currentMode.rawValue.capitalized) ?? .rule }
        .onChange(of: appState.currentMode) { _, mode in
            selectedTab = ProxyTab(rawValue: mode.rawValue.capitalized) ?? .rule
        }
        .task(id: "\(profileKey)|\(clashViewModel.isRunning)|\(clashViewModel.isToggling)") {
            await refreshProxies()
        }
        .onChange(of: filteredGroups.map(\.name), initial: true) { _, names in
            if !names.contains(selectedGroup ?? "") { selectedGroup = names.first; focusedNode = nil }
        }
        .onChange(of: selectedGroup) { _, _ in focusedNode = nil }
    }

    private func refreshProxies() async {
        let revision = UUID()
        loadRevision = revision
        let key = profileKey
        let path = profileService.activeProfile?.path
        let policyKey = profileService.activeProfile.map { "policyGroupOverrides." + $0.id.uuidString }
        let policy = policyKey.flatMap { UserDefaults.standard.string(forKey: $0) } ?? "{}"
        liveProfileKey = ""
        isLoading = true
        loadError = nil
        defer { if loadRevision == revision { isLoading = false } }
        do {
            let resources = try ManagedWorkspaceService.read(profileService.activeProfileID).resources
            let snapshot: SubscriptionSnapshot? = try await Task.detached {
                guard let path else { return nil }
                let source = try String(contentsOf: path, encoding: .utf8)
                return try SubscriptionSnapshot.parse(PolicyConfiguration.preview(source: ManagedResources.apply(source: source, draft: resources), overrides: policy))
            }.value
            try Task.checkCancellation()
            guard key == profileKey, loadRevision == revision else { return }
            let types = ["select": "Selector", "url-test": "URLTest", "fallback": "Fallback", "load-balance": "LoadBalance"]
            savedNodes = Dictionary(uniqueKeysWithValues: (snapshot?.nodes ?? []).map {
                ($0.name, ProxyNode(id: $0.name, name: $0.name, type: $0.type))
            })
            savedGroups = (snapshot?.groups ?? []).map {
                ProxyGroup(name: $0.name, type: types[$0.type] ?? $0.type, all: $0.members)
            }
            providerCount = snapshot?.providerCount ?? 0
            savedProfileKey = key
        } catch is CancellationError { return }
        catch {
            guard key == profileKey, loadRevision == revision else { return }
            savedNodes = [:]
            savedGroups = []
            providerCount = 0
            savedProfileKey = key
            // Parser errors can include credentials from YAML; never display them.
            loadError = "Could not read the saved subscription. Update it in Subscriptions."
        }
        guard clashViewModel.isRunning, !clashViewModel.isToggling else { return }
        do {
            try await clashController.fetchProxiesData()
            try Task.checkCancellation()
            guard key == profileKey, loadRevision == revision else { return }
            guard clashViewModel.appliedProfileRevision == key, !clashController.proxyGroups.isEmpty else {
                loadError = "Showing saved nodes. Apply this subscription to load it into the core."
                return
            }
            liveProfileKey = key
        } catch is CancellationError { }
        catch {
            guard key == profileKey, loadRevision == revision else { return }
            loadError = "Showing saved nodes. Live data is unavailable."
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: DS.Space.md) {
            Picker("Mode", selection: Binding(get: { selectedTab }, set: { tab in
                Task {
                    await appState.setMode(ClashConfig.Mode(rawValue: tab.rawValue.lowercased()) ?? .rule)
                    selectedTab = ProxyTab(rawValue: appState.currentMode.rawValue.capitalized) ?? .rule
                }
            })) {
                ForEach(ProxyTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .disabled(appState.isPerformingNetworkOperation || clashViewModel.isToggling)
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()

            Spacer(minLength: DS.Space.sm)

            TextField("Search nodes", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .frame(minWidth: 130, idealWidth: 200, maxWidth: 200)

            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Button { appState.selection = .policies } label: { Image(systemName: "slider.horizontal.3") }
                        .help("Open policy groups").accessibilityLabel("Policies")
                    Button { showingResources = true } label: { Image(systemName: "square.stack") }
                        .disabled(!showingLive).help("Node resources").accessibilityLabel("Node resources")
                }

                Divider().frame(height: 14).padding(.horizontal, 4)

                HStack(spacing: 6) {
                    if !clashViewModel.isRunning {
                        Button {
                            Task { await clashViewModel.start() }
                        } label: {
                            Image(systemName: "power")
                        }
                        .accessibilityLabel("Start Core")
                        .disabled(clashViewModel.isToggling || appState.isPerformingNetworkOperation)
                        .help("Start the core to test latency; system proxy remains a separate control")
                    }

                    Button {
                        Task { await clashController.testAllProxyDelays() }
                    } label: {
                        if clashController.isTestingAllProxies {
                            ProgressView().controlSize(.mini)
                        } else {
                            ProxyLatencySymbol()
                        }
                    }
                    .disabled(!showingLive || clashController.isTestingAllProxies)
                    .help("Test all nodes · Automatically refreshed every 5 minutes while the core runs")
                    .accessibilityLabel("Test all nodes")

                    Button {
                        Task { await refreshProxies() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh nodes")
                    .disabled(isLoading)
                }
            }
            .buttonStyle(ProxyToolbarButtonStyle())
            .fixedSize()
            .padding(.leading, 8)
        }
        .padding(.horizontal, DS.Space.lg)
        .padding(.top, DS.Space.pageTop)
        .padding(.bottom, DS.Space.md)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if selectedTab == .direct {
            ContentUnavailableView {
                Label("Direct Connection", systemImage: "arrow.turn.up.right")
            } description: {
                Text("All traffic goes directly.")
            }
            .frame(maxWidth: .infinity, minHeight: 300)
        } else if filteredGroups.isEmpty {
            ContentUnavailableView {
                Label(isLoading ? "Loading subscription" : "No saved nodes", systemImage: "network.slash")
            } description: {
                Text(loadError ?? (profileService.activeProfile == nil
                    ? "Add a subscription in Subscriptions."
                    : "This subscription has no embedded nodes. Update it in Subscriptions."))
            }
            .frame(maxWidth: .infinity, minHeight: 300)
        } else {
            VStack(spacing: 0) {
                if !showingLive {
                    Text(loadError ?? (providerCount > 0
                        ? "Saved subscription · Provider nodes load when the core runs."
                        : "Saved subscription · Choices apply when you connect."))
                        .font(DS.Typography.metadata).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, DS.Space.lg).padding(.vertical, DS.Space.sm)
                }
                ProxyWorkspaceTable(
                    groups: filteredGroups.map { group in
                        .init(id: group.name, type: group.type, current: group.type == "LoadBalance" ? nil : group.now,
                              count: group.all.count, matches: !matchingNodes(group).isEmpty)
                    },
                    selectedGroup: $selectedGroup, focusedNode: $focusedNode,
                    rows: tableRows, search: searchText,
                    canSelect: currentGroup?.supportsManualSelection == true && !selectionBusy,
                    canTest: showingLive,
                    automatic: currentGroup?.supportsAutomaticSelection == true,
                    pinned: currentGroup?.manualSelection != nil,
                    busy: selectionBusy,
                    onSelect: selectNode, onTest: testNode, onResume: resumeAutomatic
                )
            }
        }
    }

    private var selectionBusy: Bool { clashViewModel.isToggling || appState.isPerformingNetworkOperation }
    private var currentGroup: ProxyGroup? { filteredGroups.first { $0.name == selectedGroup } ?? filteredGroups.first }
    private func matchingNodes(_ group: ProxyGroup) -> [String] {
        group.all.filter { searchText.isEmpty || $0.localizedCaseInsensitiveContains(searchText) }
    }
    private var tableRows: [ProxyTableRow] {
        guard let group = currentGroup else { return [] }
        let groupTypes = Dictionary(displayGroups.map { ($0.name, $0.type) }, uniquingKeysWith: { first, _ in first })
        return ProxyNodeOrder.sorted(matchingNodes(group)) { displayNodes[$0]?.delay }.map { name in
            .init(id: name, type: groupTypes[name] ?? displayNodes[name]?.type ?? (name == "DIRECT" ? "Direct" : "—"),
                  delay: displayNodes[name]?.delay,
                  selected: group.manualSelection == name,
                  active: group.type != "LoadBalance" && group.now == name,
                  testing: clashController.testingProxyNames.contains(name))
        }
    }
    private func selectNode(_ name: String) {
        guard let group = currentGroup, !selectionBusy, group.supportsManualSelection, group.all.contains(name) else { return }
        Task {
            do { try await profileService.selectNode(group: group, node: name) }
            catch { appState.reportError(error.localizedDescription) }
        }
    }
    private func testNode(_ name: String) {
        guard showingLive, !clashController.testingProxyNames.contains(name) else { return }
        Task { _ = try? await clashController.testProxyDelay(name: name) }
    }
    private func resumeAutomatic() {
        guard let group = currentGroup, group.supportsAutomaticSelection, group.manualSelection != nil, !selectionBusy else { return }
        Task {
            do { try await profileService.clearNodeSelection(group: group) }
            catch { appState.reportError(error.localizedDescription) }
        }
    }
}

/// Stable hit areas keep the utility icons quiet and comfortably separated.
private struct ProxyToolbarButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(isEnabled ? Color.primary.opacity(0.75) : Color.secondary.opacity(0.4))
            .frame(width: 28, height: 28)
            .background(Color.primary.opacity(configuration.isPressed ? 0.10 : hovering && isEnabled ? 0.05 : 0), in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}
