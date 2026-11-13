import SwiftUI
import Combine
import UniformTypeIdentifiers

// MARK: - Grouping

// MARK: - Connections View

struct ConnectionsView: View {
    @StateObject private var viewModel = ConnectionsViewModel()
    @State private var searchText = ""
    @State private var selectedNodeID: ActivityNode.ID? // For Inspector
    @State private var showInspector: Bool = false

    // Sort orders
    @State private var sessionSortOrder = [KeyPathComparator(\ActivityNode.sortValue, order: .reverse)]

    var body: some View {
        HSplitView {
            // Main Content
            VStack(spacing: DS.Space.md) {
                // Toolbar
                DSCard(padding: DS.Space.md) {
                    toolbarView
                }
                .fixedSize(horizontal: false, vertical: true)

                // Table
                hierarchicalTable
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, DS.Space.lg)
            .padding(.bottom, DS.Space.lg)
            .padding(.top, DS.Space.pageTop)
            .background(DS.canvas)
            .layoutPriority(1)
            .frame(minWidth: 400)

            // Inspector Sidebar
            if showInspector {
                ConnectionInspectorView(nodeID: selectedNodeID, viewModel: viewModel)
                    .frame(minWidth: 280, maxWidth: 400)
            }
        }
        .toolbar {
            ActivityTitleToolbar(count: viewModel.groupedNodes.count,
                                 subtitle: "Connections",
                                 download: formatBytes(viewModel.totalDownload),
                                 upload: formatBytes(viewModel.totalUpload))
        }
        .alert("Activity action failed", isPresented: Binding(get: { viewModel.actionError != nil }, set: { if !$0 { viewModel.actionError = nil } })) {
            Button("OK") { viewModel.actionError = nil }
        } message: { Text(viewModel.actionError ?? "") }
        .onChange(of: viewModel.groupingMode) { _, _ in selectedNodeID = nil }
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
        HStack(spacing: DS.Space.md) {
            // Grouping Picker
            Picker("", selection: $viewModel.groupingMode) {
                ForEach(GroupingMode.allCases) { mode in
                    Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.small)
            .frame(minWidth: 240, idealWidth: 320)

            Spacer(minLength: DS.Space.sm)

            // Search
            TextField("Search activity", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .frame(minWidth: 130, idealWidth: 200, maxWidth: 200)

            // Actions
            HStack(spacing: DS.Space.xs) {
                Button {
                    viewModel.resetStatistics()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(DS.Typography.secondary.weight(.medium))
                }
                .buttonStyle(.borderless)
                .help("Reset Usage Statistics")

                Button {
                    withAnimation { showInspector.toggle() }
                } label: {
                    Image(systemName: "sidebar.right")
                        .font(DS.Typography.secondary.weight(.medium))
                        .foregroundStyle(showInspector ? AnyShapeStyle(HierarchicalShapeStyle.primary) : AnyShapeStyle(HierarchicalShapeStyle.tertiary))
                }
                .buttonStyle(.borderless)
                .help("Toggle Inspector")

                Button {
                    exportConnections()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(DS.Typography.secondary.weight(.medium))
                }
                .buttonStyle(.borderless)
                .help("Export Data")
            }
        }
    }

    // MARK: - Hierarchical Table
    private var hierarchicalTable: some View {
        Group {
            if nodes.isEmpty {
                DSCard(padding: DS.Space.xxl, spacing: 0) {
                    ContentUnavailableView {
                        Label(emptyActivityTitle, systemImage: "arrow.left.arrow.right.circle")
                    } description: {
                        Text(emptyActivityDescription)
                    }
                }
            } else {
                DSCard(padding: 0, spacing: 0) {
                    Table(nodes, children: \.children, selection: $selectedNodeID, sortOrder: $sessionSortOrder) {
                        TableColumn("Process / Host", value: \.title) { node in
                            HStack(spacing: DS.Space.sm) {
                                iconView(for: node)
                                    .frame(width: 20, height: 20)
                                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                                VStack(alignment: .leading, spacing: 1.5) {
                                    Text(node.title)
                                        .font(DS.Typography.body.weight(.medium))
                                        .lineLimit(1)

                                    // Subtitles
                                    switch node {
                                    case .app(let session):
                                        if session.activeConnectionCount > 0 {
                                            HStack(spacing: DS.Space.xs) {
                                                Circle()
                                                    .fill(Color.statusGood)
                                                    .frame(width: 4, height: 4)
                                                Text("\(session.activeConnectionCount) active")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                        } else {
                                            Text("Inactive")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    case .group(let group):
                                        Text("\(group.activeCount) active")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    case .connection(let conn):
                                        Text(conn.chainsString)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer(minLength: DS.Space.sm)

                                // Sparkline (Only for Apps currently)
                                switch node {
                                case .app(let session):
                                    if !session.speedHistory.isEmpty {
                                        SparklineView(data: session.speedHistory, color: .seriesDown)
                                            .frame(width: 60, height: 22)
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
                            case .app(let x): trafficCell(bytes: x.totalDownload, speed: x.currentDownloadSpeed, color: .seriesDown, arrow: "arrow.down")
                            case .group(let x): trafficCell(bytes: x.download, speed: x.downloadSpeed, color: .seriesDown, arrow: "arrow.down")
                            case .connection(let x): trafficCell(bytes: x.download, speed: x.downloadSpeed, color: .seriesDown, arrow: "arrow.down")
                            }
                        }
                        .width(ideal: 100)

                        TableColumn("Upload", value: \.uploadSortValue) { node in
                            switch node {
                            case .app(let x): trafficCell(bytes: x.totalUpload, speed: x.currentUploadSpeed, color: .seriesUp, arrow: "arrow.up")
                            case .group(let x): trafficCell(bytes: x.upload, speed: x.uploadSpeed, color: .seriesUp, arrow: "arrow.up")
                            case .connection(let x): trafficCell(bytes: x.upload, speed: x.uploadSpeed, color: .seriesUp, arrow: "arrow.up")
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
                    .scrollIndicators(.never)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                }
            }
        }
    }

    private var emptyActivityTitle: String {
        viewModel.groupedNodes.isEmpty ? "No network activity" : "No matching activity"
    }

    private var emptyActivityDescription: String {
        viewModel.groupedNodes.isEmpty ? "Active processes and connections will appear here." : "Change the search field to show activity."
    }

    private func copyToClipboard(_ content: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
    }

    // Computed Nodes for Table
    var nodes: [ActivityNode] {
        ActivityPresentation.sorted(ActivityPresentation.filter(viewModel.groupedNodes, query: searchText), using: sessionSortOrder)
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
                     .foregroundStyle(.secondary)
             } else {
                 ApplicationIconView(path: iconPath)
             }
         } else {
             Image(systemName: "circle.fill")
                 .resizable()
                 .frame(width: 5, height: 5)
                 .foregroundStyle(.tertiary)
         }
    }

    private func trafficCell(bytes: Int64, speed: Int64, color: Color, arrow: String) -> some View {
        VStack(alignment: .leading, spacing: 1.5) {
            Text(formatBytes(bytes))
                .font(DS.Typography.metadata.monospaced().weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.primary)

            if speed > 0 {
                HStack(spacing: 3) {
                    Image(systemName: arrow)
                        .font(DS.Typography.caption.weight(.semibold))
                        .foregroundStyle(color)
                    Text("\(formatSpeed(speed))")
                        .font(DS.Typography.caption.monospaced())
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("—")
                    .font(DS.Typography.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func formatSpeed(_ bytesPerSecond: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        let formatted = formatter.string(fromByteCount: bytesPerSecond)
        return formatted == "Zero KB" ? "0 KB/s" : formatted + "/s"
    }

    private func exportConnections() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.commaSeparatedText]
        panel.nameFieldStringValue = "Ares_Activity_Export_\(Date().ISO8601Format()).csv"

        // Export the visible filtered connections, deduplicated across parent rows.
        var seen = Set<String>()
        let exportedConnections = nodes.flatMap { node -> [Connection] in
            switch node {
            case .app(let session): return session.activeConnections
            case .group(let group): return group.connections
            case .connection(let connection): return [connection]
            }
        }.filter { seen.insert($0.id).inserted }
        panel.begin { response in
            if response == .OK, let url = panel.url {
                Task {
                    await viewModel.exportData(to: url, connections: exportedConnections)
                }
            }
        }
    }
}
