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
    @State private var expandedGroups = Set<String>()
    @State private var searchText = ""
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

            ScrollView(showsIndicators: false) {
                content
            }
        }
        .navigationTitle("")
        .toolbar { ProxiesTitleToolbar(count: nodeCount) }
        .onAppear { selectedTab = ProxyTab(rawValue: appState.currentMode.rawValue.capitalized) ?? .rule }
        .onChange(of: appState.currentMode) { _, mode in
            selectedTab = ProxyTab(rawValue: mode.rawValue.capitalized) ?? .rule
        }
        .task(id: "\(profileKey)|\(clashViewModel.isRunning)|\(clashViewModel.isToggling)") {
            await refreshProxies()
        }
        .onChange(of: displayGroups.map(\.name)) { _, names in
            expandedGroups.formUnion(names)
        }
    }

    private func refreshProxies() async {
        let revision = UUID()
        loadRevision = revision
        let key = profileKey
        let path = profileService.activeProfile?.path
        liveProfileKey = ""
        isLoading = true
        loadError = nil
        defer { if loadRevision == revision { isLoading = false } }
        do {
            let snapshot: SubscriptionSnapshot? = try await Task.detached {
                guard let path else { return nil }
                return try SubscriptionSnapshot.parse(String(contentsOf: path, encoding: .utf8))
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
            expandedGroups = Set(savedGroups.map(\.name)).union(["GLOBAL"])
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
            expandedGroups.formUnion(clashController.proxyGroups.map(\.name))
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

            HStack(spacing: DS.Space.xs) {
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
            .font(DS.Typography.secondary.weight(.medium))
            .buttonStyle(.borderless)
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
            LazyVStack(spacing: DS.Space.md) {
                if !showingLive {
                    Text(loadError ?? (providerCount > 0
                        ? "Saved subscription · Provider nodes load when the core runs."
                        : "Saved subscription · Select a node now; it will be applied when you connect."))
                        .font(DS.Typography.metadata)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(filteredGroups) { group in
                    SimpleProxyGroupCard(
                        group: group,
                        nodes: displayNodes,
                        allowsRuntimeActions: showingLive,
                        isExpanded: expandedGroups.contains(group.name) || !searchText.isEmpty, // Auto expand on search
                        searchText: searchText,
                        onToggle: {
                            if expandedGroups.contains(group.name) {
                                expandedGroups.remove(group.name)
                            } else {
                                expandedGroups.insert(group.name)
                            }
                        }
                    )
                }
            }
            .padding(DS.Space.lg)
        }
    }
}

// MARK: - Group card

struct SimpleProxyGroupCard: View {
    let group: ProxyGroup
    let nodes: [String: ProxyNode]
    let allowsRuntimeActions: Bool
    let isExpanded: Bool
    let searchText: String
    let onToggle: () -> Void

    @EnvironmentObject var clashController: ClashController
    @EnvironmentObject var profileService: ProfileService
    @EnvironmentObject var clashViewModel: ClashViewModel
    @EnvironmentObject var appState: AppState

    var body: some View {
        DSCard(padding: 0, spacing: 0, radius: DS.Radius.card) {
            HStack(spacing: 0) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        onToggle()
                    }
                } label: {
                    headerRow
                }
                .buttonStyle(.plain)

                if group.supportsAutomaticSelection {
                    Button {
                        Task {
                            do { try await profileService.clearNodeSelection(group: group) }
                            catch { AppState.shared.reportError(error.localizedDescription) }
                        }
                    } label: {
                        Label("Auto", systemImage: group.manualSelection == nil ? "checkmark" : "arrow.triangle.2.circlepath")
                            .font(DS.Typography.metadata)
                    }
                    .buttonStyle(.borderless)
                    .disabled(group.manualSelection == nil || clashViewModel.isToggling || appState.isPerformingNetworkOperation)
                    .help("Let this group choose nodes automatically")
                    .padding(.trailing, DS.Space.md)
                }
            }

            if isExpanded {
                Rectangle()
                    .fill(Color(nsColor: .separatorColor).opacity(0.8))
                    .frame(height: DS.hairline)

                nodeGrid
            }
        }
    }

    // MARK: Header

    private var headerRow: some View {
        HStack(spacing: DS.Space.sm + 2) {
            Image(systemName: groupIcon)
                .font(DS.Typography.metadata.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                )

            Text(group.name)
                .font(DS.Typography.body.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)

            DSTag(text: group.type)

            Spacer(minLength: DS.Space.sm)

            if let now = group.now {
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 5, height: 5)
                    Text(now)
                        .font(DS.Typography.metadata)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Image(systemName: "chevron.right")
                .font(DS.Typography.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
        }
        .padding(.horizontal, DS.Space.md)
        .padding(.vertical, DS.Space.sm + 2)
        .contentShape(Rectangle())
    }

    // MARK: Nodes

    @ViewBuilder
    private var nodeGrid: some View {
        let filteredItems = group.all.filter { itemName in
            searchText.isEmpty || itemName.localizedCaseInsensitiveContains(searchText)
        }

        let sortedItems = ProxyNodeOrder.sorted(filteredItems) { nodes[$0]?.delay }

        if !sortedItems.isEmpty {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 168), spacing: DS.Space.sm)],
                spacing: DS.Space.sm
            ) {
                ForEach(sortedItems, id: \.self) { itemName in
                    SimpleProxyButton(
                        name: itemName,
                        isSelected: group.manualSelection == itemName,
                        delay: nodes[itemName]?.delay,
                        isTesting: clashController.testingProxyNames.contains(itemName),
                        canSelect: group.supportsManualSelection && !clashViewModel.isToggling && !appState.isPerformingNetworkOperation,
                        canTest: allowsRuntimeActions,
                        onSelect: {
                            Task {
                                do { try await profileService.selectNode(group: group, node: itemName) }
                                catch { AppState.shared.reportError(error.localizedDescription) }
                            }
                        },
                        onTest: {
                            guard allowsRuntimeActions else { return }
                            Task {
                                _ = try? await clashController.testProxyDelay(name: itemName)
                            }
                        }
                    )

                }
            }
            .padding(DS.Space.md)
        } else if !searchText.isEmpty {
            Text("No nodes matching \"\(searchText)\"")
                .font(DS.Typography.metadata)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(DS.Space.md)
        }
    }

    private var groupIcon: String {
        switch group.type {
        case "Selector": return "hand.tap"
        case "URLTest": return "speedometer"
        case "Fallback": return "arrow.triangle.2.circlepath"
        case "LoadBalance": return "scale.3d"
        default: return "network"
        }
    }
}
