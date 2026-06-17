import SwiftUI
import Combine
import UniformTypeIdentifiers

// MARK: - Grouping

enum GroupingMode: String, CaseIterable, Identifiable {
    case app = "Application"
    case proxy = "Proxy Node"
    case host = "Host / Domain"
    case rule = "Rule"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .app: return "app"
        case .proxy: return "network"
        case .host: return "globe"
        case .rule: return "list.bullet.rectangle"
        }
    }
}

// MARK: - Connections View

struct ConnectionsView: View {
    @StateObject private var viewModel = ConnectionsViewModel()
    @State private var searchText = ""
    @State private var selectedNodeID: ActivityNode.ID? // For Inspector
    @State private var showInspector: Bool = true

    // Sort orders
    @State private var sessionSortOrder = [KeyPathComparator(\ActivityNode.sortValue, order: .reverse)]

    var body: some View {
        HSplitView {
            // Main Content
            VStack(spacing: 0) {
                // Toolbar
                toolbarView
                    .padding()
                    .background(Color(nsColor: .windowBackgroundColor))

                Divider()

                // Table
                hierarchicalTable
            }
            .layoutPriority(1)
            .frame(minWidth: 400)

            // Inspector Sidebar
            if showInspector {
                ConnectionInspectorView(nodeID: selectedNodeID, viewModel: viewModel)
                    .frame(minWidth: 280, maxWidth: 400)
            }
        }
        .navigationTitle("Activity")
        .task {
            // Initial Start (Defer slightly to let UI settle)
            try? await Task.sleep(nanoseconds: 200_000_000)
            if scenePhase == .active {
                await viewModel.startMonitoring()
            }
        }
        .onDisappear {
            viewModel.stopMonitoring()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await viewModel.startMonitoring() }
            } else if newPhase == .background {
                viewModel.stopMonitoring()
            }
        }
    }

    @Environment(\.scenePhase) private var scenePhase

    // MARK: - Toolbar

    private var toolbarView: some View {
        HStack(spacing: 12) {
            // Grouping Picker
            Picker("", selection: $viewModel.groupingMode) {
                ForEach(GroupingMode.allCases) { mode in
                    Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 320)

            // Stats Summary
            HStack(spacing: 16) {
                Divider().frame(height: 14)

                HStack(spacing: 12) {
                    Text("\(viewModel.groupedNodes.count) items")
                        .fontWeight(.medium)

                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down").foregroundStyle(.blue)
                        Text(formatBytes(viewModel.totalDownload))
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up").foregroundStyle(.orange)
                        Text(formatBytes(viewModel.totalUpload))
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Spacer()

            // Search
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(6)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
            .frame(width: 200)

            // Actions
            HStack(spacing: 0) {
                Button {
                    viewModel.resetStatistics()
                } label: {
                    Image(systemName: "arrow.counterclockwise").fontWeight(.medium)
                }
                .help("Reset Usage Statistics")
                .buttonStyle(.plain)
                .padding(.horizontal, 8)

                Divider().frame(height: 12)

                Button {
                    withAnimation { showInspector.toggle() }
                } label: {
                    Image(systemName: "sidebar.right")
                        .fontWeight(.medium)
                        .foregroundStyle(showInspector ? .primary : .secondary)
                }
                .help("Toggle Inspector")
                .buttonStyle(.plain)
                .padding(.horizontal, 8)

                Button {
                    exportConnections()
                } label: {
                    Image(systemName: "square.and.arrow.up").fontWeight(.medium)
                }
                .help("Export Data")
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
            }
        }
    }

    // MARK: - Hierarchical Table
    private var hierarchicalTable: some View {
        Table(nodes, children: \.children, selection: $selectedNodeID, sortOrder: $sessionSortOrder) {
            TableColumn("Process / Host", value: \.title) { node in
                HStack {
                    iconView(for: node)
                        .frame(width: 24, height: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(node.title)
                            .fontWeight(.medium)

                        // Subtitles
                        switch node {
                        case .app(let session):
                            if session.activeConnectionCount > 0 {
                                Text("\(session.activeConnectionCount) active").font(.caption2).foregroundStyle(.green)
                            } else {
                                Text("Terminated").font(.caption2).foregroundStyle(.secondary)
                            }
                        case .group(let group):
                            Text("\(group.activeCount) active").font(.caption2).foregroundStyle(.primary)
                        case .connection(let conn):
                             Text(conn.chainsString).font(.caption2).foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    // Sparkline (Only for Apps currently)
                    switch node {
                    case .app(let session):
                        if !session.speedHistory.isEmpty {
                            SparklineView(data: session.speedHistory, color: .blue)
                                .frame(width: 60, height: 24)
                        }
                    default:
                        EmptyView()
                    }
                }
            }
            .width(min: 250, ideal: 320)

            TableColumn("Download", value: \.sortValue) { node in
                // Use sortValue for sorting, but we need formatting
                switch node {
                case .app(let x): trafficCell(bytes: x.totalDownload, speed: x.currentDownloadSpeed, color: .blue, arrow: "arrow.down")
                case .group(let x): trafficCell(bytes: x.download, speed: x.downloadSpeed, color: .blue, arrow: "arrow.down")
                case .connection(let x): trafficCell(bytes: x.download, speed: x.downloadSpeed, color: .blue, arrow: "arrow.down")
                }
            }
            .width(ideal: 100)

            TableColumn("Upload") { node in
                switch node {
                case .app(let x): trafficCell(bytes: x.totalUpload, speed: x.currentUploadSpeed, color: .orange, arrow: "arrow.up")
                case .group(let x): trafficCell(bytes: x.upload, speed: x.uploadSpeed, color: .orange, arrow: "arrow.up")
                case .connection(let x): trafficCell(bytes: x.upload, speed: x.uploadSpeed, color: .orange, arrow: "arrow.up")
                }
            }
            .width(ideal: 100)

        }
        .contextMenu(forSelectionType: ActivityNode.ID.self) { selection in
             // Context Menu for Selected Items
            if selection.count == 1, let id = selection.first, let node = findNode(id: id, nodes: nodes) {
                 // --- Standard Copy Actions ---
                 Button("Copy Summary") {
                     NSPasteboard.general.clearContents()
                     NSPasteboard.general.setString(node.title, forType: .string)
                 }

                 Divider()

                 // --- Detailed Actions ---
                 if case .connection(let conn) = node {
                     // Host
                     if !conn.metadata.host.isEmpty {
                         Button("Copy Host") {
                            copyToClipboard(conn.metadata.host)
                         }
                     }

                     // IP
                     Button("Copy Remote IP") {
                         copyToClipboard(conn.metadata.destinationIP)
                     }

                     // Address
                     Button("Copy Remote Address") {
                         copyToClipboard("\(conn.metadata.destinationIP):\(conn.metadata.destinationPort)")
                     }

                     Button("Copy Source Address") {
                         copyToClipboard("\(conn.metadata.sourceIP):\(conn.metadata.sourcePort)")
                     }

                     // Rule
                     if !conn.rule.isEmpty {
                         Button("Copy Rule") {
                             copyToClipboard(conn.rule)
                         }
                     }

                     Divider()

                     Button("Close Connection") {
                         Task { await viewModel.closeConnection(id: conn.id) }
                     }
                 }

                if case .app(let session) = node {
                    Button("Copy Process Path") {
                        copyToClipboard(session.id)
                    }

                    Divider()

                    Button("Force Termination (Aggressive)") {
                        viewModel.killProcess(for: session)
                    }
                }
             }
        }
        .scrollIndicators(.hidden)
    }

    private func copyToClipboard(_ content: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
    }

    // Computed Nodes for Table
    var nodes: [ActivityNode] {
        let all = viewModel.groupedNodes
        if searchText.isEmpty { return all.sorted(using: sessionSortOrder) }
        return all.filter { $0.title.localizedCaseInsensitiveContains(searchText) }.sorted(using: sessionSortOrder)
    }

    private func findNode(id: String, nodes: [ActivityNode]) -> ActivityNode? {
        for node in nodes {
             if node.id == id { return node }
             if let children = node.children {
                 if let found = findNode(id: id, nodes: children) { return found }
             }
         }
         return nil
    }

    // MARK: - Helpers

    @ViewBuilder
    private func iconView(for node: ActivityNode) -> some View {
         if let iconPath = node.icon {
             if iconPath == "network" || iconPath == "globe" || iconPath == "list.bullet.rectangle" {
                 Image(systemName: iconPath)
                     .resizable()
                     .aspectRatio(contentMode: .fit)
                     .foregroundStyle(.purple)
             } else {
                 ApplicationIconView(path: iconPath)
             }
         } else {
             Image(systemName: "circle.fill")
                 .resizable()
                 .frame(width: 6, height: 6)
                 .foregroundStyle(.secondary)
         }
    }

    private func trafficCell(bytes: Int64, speed: Int64, color: Color, arrow: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(formatBytes(bytes))
                .font(.system(.footnote, design: .monospaced))
                .fontWeight(.medium)

            if speed > 0 {
                HStack(spacing: 2) {
                    Image(systemName: arrow)
                    Text("\(formatSpeed(speed))")
                }
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(color)
            } else {
                Text("—").font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func formatSpeed(_ bytesPerSecond: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        let formatted = formatter.string(fromByteCount: bytesPerSecond)
        return formatted == "Zero KB" ? "0 KB/s" : formatted + "/s"
    }

    private func exportConnections() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.commaSeparatedText]
        panel.nameFieldStringValue = "Ares_Activity_Export_\(Date().ISO8601Format()).csv"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                Task {
                    await viewModel.exportData(to: url)
                }
            }
        }
    }
}
