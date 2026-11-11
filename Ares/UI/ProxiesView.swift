import SwiftUI
import Combine

enum ProxyTab: String, CaseIterable, Identifiable {
    case rule = "Rule"
    case global = "Global"
    case direct = "Direct"

    var id: String { rawValue }
}

struct ProxiesView: View {
    @EnvironmentObject var clashController: ClashController
    @EnvironmentObject var profileService: ProfileService
    @State private var selectedTab: ProxyTab = .rule
    @State private var expandedGroups = Set<String>()
    @State private var testingNodes = Set<String>()
    @State private var searchText = ""
    @State private var sortMode: SortMode = .default

    enum SortMode: String, CaseIterable, Identifiable {
        case `default` = "Default"
        case name = "Name"
        case delay = "Delay"
        var id: String { rawValue }
    }

    // Filter groups based on selected tab
    var filteredGroups: [ProxyGroup] {
        switch selectedTab {
        case .rule:
            let allGroups = clashController.proxyGroups.filter { $0.name != "GLOBAL" }
            return allGroups.sorted { a, b in
                if a.name == "🚀 节点选择" { return true }
                if b.name == "🚀 节点选择" { return false }
                return a.name < b.name
            }
        case .global:
            return clashController.proxyGroups.filter { $0.name == "GLOBAL" }
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
        .task {
            await Task.yield()
            DispatchQueue.main.async {
                // Default: all collapsed (empty set)
                expandedGroups = []
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: DS.Space.md) {
            Picker("Mode", selection: $selectedTab) {
                ForEach(ProxyTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()

            TextField("Search nodes", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .frame(width: 200)

            Spacer(minLength: DS.Space.sm)

            Menu {
                ForEach(SortMode.allCases) { mode in
                    Button {
                        sortMode = mode
                    } label: {
                        if sortMode == mode {
                            Label(mode.rawValue, systemImage: "checkmark")
                        } else {
                            Text(mode.rawValue)
                        }
                    }
                }
            } label: {
                HStack(spacing: DS.Space.xs) {
                    Image(systemName: "arrow.up.arrow.down")
                    Text(sortMode.rawValue)
                }
                .font(DS.Typography.metadata.weight(.medium))
                .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Sort nodes")

            Text("\(clashController.proxyNodes.count) nodes")
                .font(DS.Typography.metadata)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, DS.Space.lg)
        .padding(.vertical, DS.Space.md)
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
                Label("No proxy groups", systemImage: "network.slash")
            } description: {
                Text("Start Clash to see proxies.")
            }
            .frame(maxWidth: .infinity, minHeight: 300)
        } else {
            LazyVStack(spacing: DS.Space.md) {
                ForEach(filteredGroups) { group in
                    SimpleProxyGroupCard(
                        group: group,
                        isExpanded: expandedGroups.contains(group.name) || !searchText.isEmpty, // Auto expand on search
                        searchText: searchText,
                        sortMode: sortMode,
                        testingNodes: $testingNodes,
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
    let isExpanded: Bool
    let searchText: String
    let sortMode: ProxiesView.SortMode
    @Binding var testingNodes: Set<String>
    let onToggle: () -> Void

    @EnvironmentObject var clashController: ClashController

    var body: some View {
        DSCard(padding: 0, spacing: 0, radius: DS.Radius.card) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    onToggle()
                }
            } label: {
                headerRow
            }
            .buttonStyle(.plain)

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

        let sortedItems = filteredItems.sorted { a, b in
            switch sortMode {
            case .default:
                return false // Keep original order
            case .name:
                return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
            case .delay:
                let delayA = clashController.proxyNodes[a]?.delay ?? 99999
                let delayB = clashController.proxyNodes[b]?.delay ?? 99999
                return delayA < delayB
            }
        }

        if !sortedItems.isEmpty {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 168), spacing: DS.Space.sm)],
                spacing: DS.Space.sm
            ) {
                ForEach(sortedItems, id: \.self) { itemName in
                    SimpleProxyButton(
                        name: itemName,
                        isSelected: group.now == itemName,
                        delay: clashController.proxyNodes[itemName]?.delay,
                        isTesting: testingNodes.contains(itemName),
                        onSelect: {
                            Task {
                                do {
                                    try await clashController.selectProxy(
                                        group: group.name,
                                        proxy: itemName
                                    )
                                    // Refresh proxy data to update UI
                                    try await clashController.fetchProxiesData()
                                } catch {
                                    AppState.shared.reportError("Could not select \(itemName): \(error.localizedDescription)")
                                }
                            }
                        },
                        onTest: {
                            testingNodes.insert(itemName)
                            Task {
                                _ = try? await clashController.testProxyDelay(name: itemName)
                                testingNodes.remove(itemName)
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
