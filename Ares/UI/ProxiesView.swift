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
    
    // Filter groups based on selected tab
    var filteredGroups: [ProxyGroup] {
        switch selectedTab {
        case .rule:
            // Show ALL groups except GLOBAL
            // 节点选择 must be first!
            let allGroups = clashController.proxyGroups.filter { $0.name != "GLOBAL" }
            return allGroups.sorted { a, b in
                if a.name == "🚀 节点选择" { return true }
                if b.name == "🚀 节点选择" { return false }
                return a.name < b.name
            }
        case .global:
            // Only GLOBAL
            return clashController.proxyGroups.filter { $0.name == "GLOBAL" }
        case .direct:
            return []
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab selector
            Picker("Mode", selection: $selectedTab) {
                ForEach(ProxyTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            
            Divider()
            
            // Content
            ScrollView {
                if selectedTab == .direct {
                    VStack(spacing: 12) {
                        Image(systemName: "arrow.forward.circle")
                            .font(.system(size: 48))
                            .foregroundStyle(.green)
                        Text("Direct Connection")
                            .font(.title2)
                            .fontWeight(.medium)
                        Text("All traffic goes directly")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(60)
                } else if filteredGroups.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "network.slash")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("No proxy groups available")
                            .foregroundStyle(.secondary)
                        Text("Start Clash to see proxies")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(60)
                } else {
                    VStack(spacing: 16) {
                        ForEach(filteredGroups) { group in
                            SimpleProxyGroupCard(
                                group: group,
                                isExpanded: expandedGroups.contains(group.name),
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
        .navigationTitle("Proxies")
        .onAppear {
            Task {
                try? await clashController.fetchProxiesData()
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
    @Binding var testingNodes: Set<String>
    let onToggle: () -> Void
    
    @EnvironmentObject var clashController: ClashController
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header - clickable entire row
            Button(action: onToggle) {
                HStack {
                    Image(systemName: groupIcon)
                        .foregroundStyle(.blue)
                    
                    Text(group.name)
                        .font(.headline)
                    
                    Spacer()
                    
                    // Current selection
                    if let now = group.now {
                        Text(now)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(6)
                    }
                    
                    Text(group.type)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(4)
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                Divider()
                
                // Simple grid - just show all items
                let columns = [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ]
                
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(group.all, id: \.self) { itemName in
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
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private var groupIcon: String {
        switch group.type {
        case "Selector": return "checkmark.circle"
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
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .lineLimit(2)
            
            HStack(spacing: 6) {
                if let ms = delay {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(delayColor(ms))
                            .frame(width: 5, height: 5)
                        Text("\(ms)ms")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("—")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                
                Spacer()
                
                Button(action: {
                    print("[SimpleProxyButton] Test button clicked for \(name)")
                    onTest()
                }) {
                    if isTesting {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10))
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.blue.opacity(0.15) : Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isSelected ? Color.blue : Color.gray.opacity(0.2), lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(Rectangle())  // Important: make entire area tappable
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
