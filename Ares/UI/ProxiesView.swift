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
            // Header: Mode + Search + Sort
            VStack(spacing: 16) {
                HStack(spacing: 16) {
                    // Mode selector
                    Picker("Mode", selection: $selectedTab) {
                        ForEach(ProxyTab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                    
                    Spacer()
                    
                    // Sort picker
                    HStack(spacing: 6) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 12))
                        Picker("Sort", selection: $sortMode) {
                            ForEach(SortMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 100)
                        .labelsHidden()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(8)
                }
                
                // Search bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 13, weight: .medium))
                    
                    TextField("Search among \(clashController.proxyNodes.count) nodes...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                    
                    if !searchText.isEmpty {
                        Button {
                            withAnimation { searchText = "" }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // Content
            ScrollView(showsIndicators: false) {
                if selectedTab == .direct {
                    VStack(spacing: 12) {
                        Image(systemName: "arrow.turn.up.right")
                            .font(.system(size: 48, weight: .medium))
                            .foregroundStyle(.green)
                        Text("Direct Connection")
                            .font(.title2)
                            .fontWeight(.medium)
                        Text("All traffic goes directly")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(60)
                } else if filteredGroups.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "network.slash")
                            .font(.system(size: 48, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text("No proxy groups available")
                            .foregroundStyle(.secondary)
                        Text("Start Clash to see proxies")
                            .font(.footnote)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(60)
                } else {
                    VStack(spacing: 16) {
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
                    .padding()
                }
            }
        }
        .task {
            await Task.yield()
            DispatchQueue.main.async {
                // Default: all collapsed (empty set)
                expandedGroups = []
            }
        }
        .onReceive(Timer.publish(every: 10, on: .main, in: .common).autoconnect()) { _ in
            // Refresh proxy status every 10 seconds (reduced from 3s to minimize log noise)
            Task {
                try? await clashController.fetchProxiesData()
            }
        }
    }
}

// SIMPLE card - just like Clash Verge
struct SimpleProxyGroupCard: View {
    let group: ProxyGroup
    let isExpanded: Bool
    let searchText: String
    let sortMode: ProxiesView.SortMode
    @Binding var testingNodes: Set<String>
    let onToggle: () -> Void
    
    @EnvironmentObject var clashController: ClashController
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header - clickable entire row
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    onToggle()
                }
            }) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.12))
                            .frame(width: 28, height: 28)
                        Image(systemName: groupIcon)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.blue)
                    }
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text(group.name)
                            .font(.system(size: 14, weight: .bold))
                        Text(group.type)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    // Current selection
                    if let now = group.now {
                        Text(now)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.blue)
                                    .shadow(color: Color.blue.opacity(0.3), radius: 4, x: 0, y: 2)
                            )
                    }
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary.opacity(0.5))
                }
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                Divider()
                
                // Filter and Sort items
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
                        // Always keep direct/reject at top if they are in the group? 
                        // Actually let's just sort by delay.
                        return delayA < delayB
                    }
                }
                
                if !sortedItems.isEmpty {
                    // Simple grid - just show all items
                    let columns = [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ]
                    
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(sortedItems, id: \.self) { itemName in
                            SimpleProxyButton(
                                name: itemName,
                                isSelected: group.now == itemName,
                                delay: clashController.proxyNodes[itemName]?.delay,
                                isTesting: testingNodes.contains(itemName),
                                onSelect: {
                                    print("[ProxiesView] 🔵 Clicked: \(itemName) in group: \(group.name)")
                                    Task {
                                        do {
                                            print("[ProxiesView] 📡 Calling API select...")
                                            try await clashController.selectProxy(
                                                group: group.name,
                                                proxy: itemName
                                            )
                                            print("[ProxiesView] ✅ Selection successful")
                                            // Refresh proxy data to update UI
                                            try? await clashController.fetchProxiesData()
                                        } catch {
                                            print("[ProxiesView] ❌ Selection error: \(error)")
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
                    .padding(.top, 8)
                } else if !searchText.isEmpty {
                    Text("No nodes matching \"\(searchText)\"")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
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

// Simple button
struct SimpleProxyButton: View {
    let name: String
    let isSelected: Bool
    let delay: Int?
    let isTesting: Bool
    let onSelect: () -> Void
    let onTest: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(name)
                .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                .lineLimit(1)
                .foregroundStyle(isSelected ? .white : .primary)
            
            HStack(spacing: 6) {
                if let ms = delay {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(delayColor(ms))
                            .frame(width: 6, height: 6)
                        Text("\(ms)ms")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(isSelected ? .white.opacity(0.9) : .secondary)
                    }
                } else {
                    Text("No delay")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(isSelected ? .white.opacity(0.6) : Color.secondary.opacity(0.5))
                }
                
                Spacer()
                
                if isTesting {
                    if isSelected {
                        ProgressView()
                            .controlSize(.mini)
                            .colorInvert()
                    } else {
                        ProgressView()
                            .controlSize(.mini)
                    }
                } else {
                    Button {
                        onTest()
                    } label: {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 14)) // Slightly larger for tap target
                            .foregroundStyle(isSelected ? .white.opacity(0.9) : .secondary.opacity(0.4))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Test Latency")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? 
                    AnyShapeStyle(LinearGradient(colors: [.blue, .blue.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)) : 
                    AnyShapeStyle(Color.primary.opacity(0.03)))
        )
        .shadow(color: isSelected ? Color.blue.opacity(0.3) : Color.clear, radius: 4, x: 0, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.blue.opacity(0.5) : Color.primary.opacity(0.06), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            print("[SimpleProxyButton] onTapGesture triggered for: \(name)")
            onSelect()
        }
    }
    
    private func delayColor(_ ms: Int) -> Color {
        switch ms {
        case 0..<100: return .green
        case 100..<300: return .orange
        default: return .red
        }
    }
}
