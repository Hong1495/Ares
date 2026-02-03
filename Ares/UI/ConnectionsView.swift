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
        .onChange(of: scenePhase) { newPhase in
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

// ... ApplicationIconView ...

extension ConnectionsViewModel {
    func killProcess(for session: AppSession) {
        // Find PID from active connections if possible, or use `pkill` by process name/path?
        // Since we aggregated by bundle path, we might kill all instances.

        // Strategy: Iterate all active connections of this session, find PIDs (we don't store PID in public Contract yet but metadata might have it implicitly or we use path)
        // Actually, TrafficAudit logic uses path.
        // We will attempt to kill by path matching active running applications.

        if let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleURL?.path == session.id || $0.executableURL?.path == session.id
        }) {
            app.forceTerminate()
        } else {
            // Fallback: Shell kill
             let task = Process()
             task.launchPath = "/usr/bin/pkill"
             task.arguments = ["-f", session.id]
             try? task.run()
        }
    }

    func exportData(to url: URL) async {
        var csv = "Time,ID,Type,Host,RemoteIP,RemotePort,Upload,Download,Duration,Rule,Chains\n"
        for conn in self.connections {
            let line = [
                conn.start.ISO8601Format(),
                conn.id,
                conn.typeString,
                conn.metadata.host,
                conn.metadata.destinationIP,
                conn.metadata.destinationPort,
                String(conn.upload),
                String(conn.download),
                String(conn.duration),
                conn.rule,
                conn.chains.joined(separator: " -> ")
            ].map { "\"\($0)\"" }.joined(separator: ",")
            csv += line + "\n"
        }

        try? csv.write(to: url, atomically: true, encoding: .utf8)
    }
}

struct ApplicationIconView: View {
    let path: String?

    var body: some View {
        if let path = path, !path.isEmpty {
            Image(nsImage: getAppIcon(from: path))
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "app")
                .foregroundStyle(.secondary)
        }
    }

    private func getAppIcon(from processPath: String) -> NSImage {
        var url = URL(fileURLWithPath: processPath)
        while url.pathExtension != "app" && url.path != "/" {
            url = url.deletingLastPathComponent()
        }
        if url.pathExtension == "app" {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.icon(forFile: processPath)
    }
}

// MARK: - ViewModel

actor ConnectionsCalculator {
    private var previousSnapshots: [String: (up: Int64, down: Int64, time: Date)] = [:]

    func process(rawConnections: [Connection], appSessions: [AppSession], groupingMode: GroupingMode) -> [ActivityNode] {
        let now = Date()

        // 1. Calculate Speeds
        var computedConnections = rawConnections
        for i in 0..<computedConnections.count {
            let conn = computedConnections[i]
            if let prev = previousSnapshots[conn.id] {
                let timeDiff = now.timeIntervalSince(prev.time)
                if timeDiff > 0 {
                    computedConnections[i].uploadSpeed = Int64(Double(conn.upload - prev.up) / timeDiff)
                    computedConnections[i].downloadSpeed = Int64(Double(conn.download - prev.down) / timeDiff)
                }
            }
        }

        // Update Snapshots
        var newSnapshots: [String: (up: Int64, down: Int64, time: Date)] = [:]
        for conn in computedConnections {
            newSnapshots[conn.id] = (conn.upload, conn.download, now)
        }
        previousSnapshots = newSnapshots

        // 2. Grouping Logic
        return group(connections: computedConnections, sessions: appSessions, mode: groupingMode)
    }

    func regroup(connections: [Connection], sessions: [AppSession], mode: GroupingMode) -> [ActivityNode] {
        return group(connections: connections, sessions: sessions, mode: mode)
    }

    private func group(connections: [Connection], sessions: [AppSession], mode: GroupingMode) -> [ActivityNode] {
        switch mode {
        case .app:
            return sessions.map { ActivityNode.app($0) }

        case .proxy:
            let groups = Dictionary(grouping: connections) { conn -> String in
                conn.chains.last ?? "Direct"
            }
            return groups.map { id, conns in
                ActivityNode.group(ActivityGroup(id: id, title: id, icon: "network", connections: conns))
            }

        case .host:
            let groups = Dictionary(grouping: connections) { conn -> String in
                conn.metadata.host.isEmpty ? conn.metadata.destinationIP : conn.metadata.host
            }
            return groups.map { id, conns in
                ActivityNode.group(ActivityGroup(id: id, title: id, icon: "globe", connections: conns))
            }

        case .rule:
            let groups = Dictionary(grouping: connections) { conn -> String in
                conn.rule.isEmpty ? "Unmatched" : conn.rule
            }
            return groups.map { id, conns in
                ActivityNode.group(ActivityGroup(id: id, title: id, icon: "list.bullet.rectangle", connections: conns))
            }
        }
    }
}

@MainActor
final class ConnectionsViewModel: ObservableObject {
    @Published var groupedNodes: [ActivityNode] = []

    // Grouping
    @Published var groupingMode: GroupingMode = .app {
        didSet { recomputeNodes() }
    }

    // Raw Data (Cached for regrouping without new data)
    private var lastRawConnections: [Connection] = []

    // Public readonly access to connections for UI/Export
    var connections: [Connection] { lastRawConnections }

    // Dependencies
    private let calculator = ConnectionsCalculator()
    private var webSocketTask: URLSessionWebSocketTask?
    private var isMonitoring = false
    private var cancellables = Set<AnyCancellable>()
    private var lastConnectionsUpdate: Date = .distantPast
    private let minConnectionsInterval: TimeInterval = 0.25
    private var isProcessingConnections = false

    var totalDownload: Int64 {
        // TrafficAuditManager.shared.sessions is source of truth
        TrafficAuditManager.shared.sessions.reduce(0) { $0 + $1.totalDownload }
    }

    var totalUpload: Int64 {
        TrafficAuditManager.shared.sessions.reduce(0) { $0 + $1.totalUpload }
    }

    init() {
        // Bind to TrafficAuditManager
        TrafficAuditManager.shared.$sessions
            .receive(on: RunLoop.main)
            .sink { [weak self] sessions in
                // If we are in .app mode, simple update is enough?
                // Actually, TrafficAuditManager update drives the cycle usually.
                // But for pure regrouping logic, we might need this if TrafficAuditManager updates independently.
                // However, our flow is: WebSocket -> parse -> TrafficAuditManager.update -> Calculator.process -> UI.
                // This subscription might be redundant for the main flow, but good for consistency.
            }
            .store(in: &cancellables)

        // MARK: - Global Lifecycle (Event Bus)
        NotificationCenter.default.publisher(for: .appDidGoSilent)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                print("[ConnectionsVM] 🌙 Received Silence Signal - HARD STOP")
                self?.stopMonitoring()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .appDidWakeUp)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                // Ready for wakeup
            }
            .store(in: &cancellables)
    }

    func resetStatistics() {
        TrafficAuditManager.shared.reset()
    }

    private func recomputeNodes() {
        Task {
            let sessions = TrafficAuditManager.shared.sessions
            let nodes = await calculator.regroup(connections: self.lastRawConnections, sessions: sessions, mode: self.groupingMode)
            self.groupedNodes = nodes
        }
    }

    // MARK: - Monitoring

    func startMonitoring(isRetry: Bool = false) async {
        guard AppState.shared.isForeground else { return }
        if !isRetry {
            guard !isMonitoring else { return }
            isMonitoring = true
        }

        let tunEnabled = AppState.shared.tunEnabled
        let port = tunEnabled ? ClashPorts.apiTun : ClashPorts.apiNormal
        let url = URL(string: "ws://127.0.0.1:\(port)/connections")!

        webSocketTask?.cancel()
        webSocketTask = URLSession.shared.webSocketTask(with: url)
        webSocketTask?.resume()

        await receiveMessages()
    }

    func stopMonitoring() {
        isMonitoring = false
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
    }

    private func receiveMessages() async {
        guard AppState.shared.isForeground else {
            stopMonitoring()
            return
        }
        guard let webSocket = webSocketTask else { return }
        do {
            let message = try await webSocket.receive()
            switch message {
            case .string(let text): parseConnectionsData(text)
            case .data(let data): if let text = String(data: data, encoding: .utf8) { parseConnectionsData(text) }
            @unknown default: break
            }
            if isMonitoring { await receiveMessages() }
        } catch {
            if isMonitoring {
                Task {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    await self.startMonitoring(isRetry: true)
                }
            }
        }
    }

    private func parseConnectionsData(_ jsonString: String) {
        let now = Date()
        guard now.timeIntervalSince(lastConnectionsUpdate) >= minConnectionsInterval else { return }
        guard !isProcessingConnections else { return }
        lastConnectionsUpdate = now
        isProcessingConnections = true

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            defer {
                Task { @MainActor in
                    self.isProcessingConnections = false
                }
            }

            // 1. Parse JSON (Pure func)
            var rawConnections = Self.parseJSON(jsonString)

            // Critical: Filter out "Ares" self-traffic
            rawConnections.removeAll { conn in
                guard let path = conn.metadata.processPath else { return false }
                let process = (path as NSString).lastPathComponent
                return process.localizedCaseInsensitiveContains("Ares") ||
                       process.localizedCaseInsensitiveContains("com.herastudio.ares") ||
                       path.contains("/Ares.app/")
            }

            // 2. Update Traffic Audit (MainActor, but internal logic is backgrounded)
            await TrafficAuditManager.shared.update(with: rawConnections)

            // 3. Process Speed & Grouping (Background Actor)
            // Fetch latest sessions from MainActor before going to background
            let sessions = await TrafficAuditManager.shared.sessions
            let mode = await MainActor.run { self.groupingMode }

            let nodes = await self.calculator.process(rawConnections: rawConnections, appSessions: sessions, groupingMode: mode)

            // 4. Update UI
            await MainActor.run {
                self.lastRawConnections = rawConnections
                self.groupedNodes = nodes
            }
        }
    }

    // Shared formatter to avoid expensive allocation in loop
    private static let sharedDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated private static func parseJSON(_ jsonString: String) -> [Connection] {
         guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let connectionsDict = json["connections"] as? [[String: Any]] else {
            return []
        }

        var connections: [Connection] = []

        for connData in connectionsDict {
            guard let id = connData["id"] as? String,
                  let metadataDict = connData["metadata"] as? [String: Any],
                  let network = metadataDict["network"] as? String,
                  let type = metadataDict["type"] as? String,
                  let sourceIP = metadataDict["sourceIP"] as? String,
                  let destIP = metadataDict["destinationIP"] as? String,
                  let sourcePort = metadataDict["sourcePort"] as? String,
                  let destPort = metadataDict["destinationPort"] as? String,
                  let host = metadataDict["host"] as? String else {
                continue
            }

            let metadata = ConnectionMetadata(
                network: network,
                type: type,
                sourceIP: sourceIP,
                destinationIP: destIP,
                sourcePort: sourcePort,
                destinationPort: destPort,
                host: host,
                processPath: metadataDict["processPath"] as? String
            )

            let upload = connData["upload"] as? Int64 ?? 0
            let download = connData["download"] as? Int64 ?? 0
            let chains = connData["chains"] as? [String] ?? []
            let rule = connData["rule"] as? String ?? ""
            let rulePayload = connData["rulePayload"] as? String ?? ""

            var startDate = Date()
            if let startStr = connData["start"] as? String {
                startDate = Self.sharedDateFormatter.date(from: startStr) ?? Date()
            }

            let connection = Connection(
                id: id,
                metadata: metadata,
                upload: upload,
                download: download,
                start: startDate,
                chains: chains,
                rule: rule,
                rulePayload: rulePayload
            )
            connections.append(connection)
        }
        return connections
    }

    func closeConnection(id: String) async {
         let tunEnabled = AppState.shared.tunEnabled
         let port = tunEnabled ? ClashPorts.apiTun : ClashPorts.apiNormal
         guard let url = URL(string: "http://127.0.0.1:\(port)/connections/\(id)") else { return }
         var request = URLRequest(url: url)
         request.httpMethod = "DELETE"
         try? await URLSession.shared.data(for: request)
     }
}
