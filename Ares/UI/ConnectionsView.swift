import SwiftUI
import Combine
import UniformTypeIdentifiers

// MARK: - View Modes
enum ConnectionViewMode: String, CaseIterable, Identifiable {
    case connections = "Active Connections"
    case applications = "App Usage"
    
    var id: String { rawValue }
}

// MARK: - Connections View

struct ConnectionsView: View {
    @StateObject private var viewModel = ConnectionsViewModel()
    @State private var searchText = ""
    @State private var viewMode: ConnectionViewMode = .connections
    
    // Sort orders
    @State private var connectionSortOrder = [KeyPathComparator(\Connection.start, order: .reverse)]
    @State private var sessionSortOrder = [KeyPathComparator(\AppSession.totalDownload, order: .reverse)]
    
    // Filtering
    var filteredConnections: [Connection] {
        let filtered = searchText.isEmpty ? viewModel.connections : viewModel.connections.filter { conn in
            conn.metadata.host.localizedCaseInsensitiveContains(searchText) ||
            conn.metadata.destinationIP.contains(searchText) ||
            conn.rule.localizedCaseInsensitiveContains(searchText)
        }
        return filtered.sorted(using: connectionSortOrder)
    }
    
    var filteredSessions: [AppSession] {
        let filtered = searchText.isEmpty ? viewModel.appSessions : viewModel.appSessions.filter { session in
            session.name.localizedCaseInsensitiveContains(searchText)
        }
        return filtered.sorted(using: sessionSortOrder)
    }
    
    var totalDownload: Int64 {
        viewModel.appSessions.reduce(0) { $0 + $1.totalDownload }
    }
    
    var totalUpload: Int64 {
        viewModel.appSessions.reduce(0) { $0 + $1.totalUpload }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbarView
                .padding()
                .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // Content
            if viewMode == .connections {
                connectionsTable
            } else {
                applicationsTable
            }
        }
        .navigationTitle("Activity")
        .task {
            await Task.yield()
            await viewModel.startMonitoring()
        }
        .onDisappear {
            // viewModel.stopMonitoring() // Optional: keep running for background stats?
            // Users usually expect monitoring to stop to save resources, but for audit logs we might want it.
            // For now, adhere to previous behavior: Stop.
            viewModel.stopMonitoring()
        }
    }
    
    // MARK: - Toolbar
    
    private var toolbarView: some View {
        HStack(spacing: 12) {
            // View Mode Picker
            Picker("", selection: $viewMode) {
                ForEach(ConnectionViewMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 240)
            
            // Stats Summary
            HStack(spacing: 16) {
                Divider()
                    .frame(height: 14)
                
                if viewMode == .connections {
                    Text("\(filteredConnections.count) connections")
                        .font(.footnote)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 12) {
                        Text("\(filteredSessions.count) apps")
                            .fontWeight(.medium)
                        
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down")
                                .foregroundStyle(.blue)
                            Text(formatBytes(totalDownload))
                        }
                        
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up")
                                .foregroundStyle(.orange)
                            Text(formatBytes(totalUpload))
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(6)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
            .frame(width: 200)
            
            // Actions
            HStack(spacing: 0) {
                if viewMode == .connections {
                    Button {
                        Task { await viewModel.closeAllConnections() }
                    } label: {
                        Image(systemName: "trash")
                            .fontWeight(.medium)
                    }
                    .help("Close all connections")
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                } else {
                    Button {
                        viewModel.resetStatistics()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .fontWeight(.medium)
                    }
                    .help("Reset Usage Statistics")
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                }
                
                Divider().frame(height: 12)
                
                Button {
                    exportConnections()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .fontWeight(.medium)
                }
                .help("Export Data")
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
            }
        }
    }
    
    // MARK: - Connections Table (Real-time)
    
    private var connectionsTable: some View {
        Table(filteredConnections, sortOrder: $connectionSortOrder) {
            TableColumn("Host", value: \.metadata.host) { conn in
                let host = conn.metadata.host.isEmpty ? conn.metadata.destinationIP : conn.metadata.host
                Text(host)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.primary)
            }
            .width(min: 150, ideal: 250)
            
            TableColumn("Download", value: \.download) { conn in
                trafficCell(bytes: conn.download, speed: conn.downloadSpeed, color: .blue, arrow: "arrow.down")
            }
            .width(ideal: 90)
            
            TableColumn("Upload", value: \.upload) { conn in
                trafficCell(bytes: conn.upload, speed: conn.uploadSpeed, color: .orange, arrow: "arrow.up")
            }
            .width(ideal: 90)
            
            TableColumn("Chains", value: \.chainsString) { conn in
                Text(conn.chainsString).foregroundStyle(.secondary)
            }
            .width(min: 100, ideal: 200)
            
            TableColumn("Process", value: \.processName) { conn in
                Text(conn.processName)
            }
            .width(ideal: 100)
            
            TableColumn("Type", value: \.typeString) { conn in
                Text(conn.typeString).foregroundStyle(.secondary)
            }
            .width(ideal: 80)
        }
    }
    
    // MARK: - Applications Table (Accumulated)
    
    private var applicationsTable: some View {
        Table(filteredSessions, sortOrder: $sessionSortOrder) {
            TableColumn("Application", value: \.name) { session in
                HStack {
                    ApplicationIconView(path: session.iconPath)
                        .frame(width: 24, height: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.name)
                            .fontWeight(.medium)
                            .foregroundStyle(session.isRunning ? .primary : .secondary)
                        
                        if !session.isRunning {
                            Text("Terminated")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        } else if session.activeConnectionCount > 0 {
                            Text("\(session.activeConnectionCount) active")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                    }
                }
            }
            .width(min: 180, ideal: 250)
            
            TableColumn("Total Download", value: \.totalDownload) { session in
                trafficCell(bytes: session.totalDownload, speed: session.currentDownloadSpeed, color: .blue, arrow: "arrow.down")
            }
            .width(ideal: 110)
            
            TableColumn("Total Upload", value: \.totalUpload) { session in
                trafficCell(bytes: session.totalUpload, speed: session.currentUploadSpeed, color: .orange, arrow: "arrow.up")
            }
            .width(ideal: 110)
            
            TableColumn("Last Active", value: \.lastActiveTime) { session in
                Text(session.lastActiveTime.formatted(date: .omitted, time: .standard))
                    .foregroundStyle(.secondary)
            }
            .width(ideal: 80)
            
        } 
        // Note: Removed 'rows' closure as it's not needed for flat list and caused ambiguity error.
        .scrollIndicators(.hidden)
    }
    
    // Helper for traffic columns
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
                Text("—")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
    }
    
    // MARK: - Formatters
    
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
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 60 {
            return "\(Int(duration))s"
        } else if duration < 3600 {
            return "\(Int(duration / 60))m"
        } else {
            return "\(Int(duration / 3600))h \(Int((duration.truncatingRemainder(dividingBy: 3600)) / 60))m"
        }
    }
    
    private func exportConnections() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "clash-connections-\(Date().ISO8601Format()).csv"
        panel.allowedContentTypes = [UTType.commaSeparatedText]
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                var csv = "Host,Download,Upload,Chains,Rule,Process,Duration,Source,Destination,Type\n"
                for conn in filteredConnections {
                    let chains = conn.chainsString
                    let duration = Int(conn.duration)
                    csv += "\(conn.metadata.host),\(conn.download),\(conn.upload),\"\(chains)\",\(conn.rule),\(conn.processName),\(duration),\(conn.sourceString),\(conn.destinationString),\(conn.typeString)\n"
                }
                try? csv.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}

// MARK: - Subviews

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

@MainActor
final class ConnectionsViewModel: ObservableObject {
    @Published var connections: [Connection] = []
    @Published var appSessions: [AppSession] = []
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var isMonitoring = false
    private var cancellables = Set<AnyCancellable>()
    
    // Speed calculation state for active connections
    private var previousSnapshots: [String: (up: Int64, down: Int64, time: Date)] = [:]
    
    init() {
        // Bind to TrafficAuditManager
        TrafficAuditManager.shared.$sessions
            .receive(on: RunLoop.main)
            .assign(to: \.appSessions, on: self)
            .store(in: &cancellables)
    }
    
    func resetStatistics() {
        TrafficAuditManager.shared.reset()
    }
    
    func startMonitoring(isRetry: Bool = false) async {
        if !isRetry {
            guard !isMonitoring else { return }
            isMonitoring = true
        }
        
        // Use dynamic port based on TUN mode
        let tunEnabled = AppState.shared.tunEnabled
        let port = tunEnabled ? 19097 : 9097
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
        guard let webSocket = webSocketTask else { return }
        
        do {
            let message = try await webSocket.receive()
            switch message {
            case .string(let text):
                parseConnectionsData(text)
            case .data(let data):
                if let text = String(data: data, encoding: .utf8) {
                    parseConnectionsData(text)
                }
            @unknown default:
                break
            }
            if isMonitoring { await receiveMessages() }
        } catch {
            let nsError = error as NSError
            // Silence expected startup/shutdown errors
            if nsError.code != 61 && nsError.code != 57 && nsError.code != -999 {
                // print("[ConnectionsViewModel] ⚠️ WebSocket error: \(error.localizedDescription)")
            }
            if isMonitoring {
                Task {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    await self.startMonitoring(isRetry: true)
                }
            }
        }
    }
    
    private func parseConnectionsData(_ jsonString: String) {
        Task.detached(priority: .userInitiated) {
            // 1. Pure Parsing (Immutable, safe)
            let rawConnections = Self.parseJSON(jsonString)
            let now = Date()
            
            // 2. Update Traffic Audit
            await TrafficAuditManager.shared.update(with: rawConnections)
            
            // 3. Process UI State on MainActor
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                
                // Create mutable copy for speed calculation
                var computedConnections = rawConnections
                
                // Calculate Speed
                for i in 0..<computedConnections.count {
                    let conn = computedConnections[i]
                    if let prev = self.previousSnapshots[conn.id] {
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
                self.previousSnapshots = newSnapshots
                
                // Publish
                self.connections = computedConnections
            }
        }
    }
    
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
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                startDate = formatter.date(from: startStr) ?? Date()
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
        let port = tunEnabled ? 19097 : 9097
        guard let url = URL(string: "http://127.0.0.1:\(port)/connections/\(id)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        try? await URLSession.shared.data(for: request)
    }
    
    func closeAllConnections() async {
        let tunEnabled = AppState.shared.tunEnabled
        let port = tunEnabled ? 19097 : 9097
        guard let url = URL(string: "http://127.0.0.1:\(port)/connections") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        try? await URLSession.shared.data(for: request)
    }
}
