import SwiftUI
import Combine
import UniformTypeIdentifiers

// MARK: - Models

/// Connection model
struct Connection: Identifiable, Sendable {
    let id: String
    let metadata: ConnectionMetadata
    let upload: Int64
    let download: Int64
    let start: Date
    let chains: [String]
    let rule: String
    let rulePayload: String
    
    // Calculated fields for UI
    var uploadSpeed: Int64 = 0
    var downloadSpeed: Int64 = 0
    
    var duration: TimeInterval {
        Date().timeIntervalSince(start)
    }
    
    // Sorting helpers
    var chainsString: String { chains.joined(separator: " / ") }
    var processName: String {
        guard let path = metadata.processPath, !path.isEmpty else { return "Unknown" }
        return URL(fileURLWithPath: path).lastPathComponent
    }
    var sourceString: String { "\(metadata.sourceIP):\(metadata.sourcePort)" }
    var destinationString: String { "\(metadata.destinationIP):\(metadata.destinationPort)" }
    var typeString: String { "\(metadata.network.uppercased())(\(metadata.type.lowercased()))" }
}

struct ConnectionMetadata: Codable, Sendable {
    let network: String
    let type: String
    let sourceIP: String
    let destinationIP: String
    let sourcePort: String
    let destinationPort: String
    let host: String
    let processPath: String?
   
    enum CodingKeys: String, CodingKey {
        case network, type
        case sourceIP = "sourceIP"
        case destinationIP = "destinationIP"
        case sourcePort = "sourcePort"
        case destinationPort = "destinationPort"
        case host
        case processPath
    }
}

/// Aggregated statistics for a single application
struct ApplicationStats: Identifiable, Sendable {
    let id: String              // Process path or "Unknown"
    let name: String            // Display name
    var iconPath: String?       // For icon retrieval
    var upload: Int64
    var download: Int64
    var uploadSpeed: Int64
    var downloadSpeed: Int64
    var connectionCount: Int
    
    var totalTraffic: Int64 { upload + download }
    var totalSpeed: Int64 { uploadSpeed + downloadSpeed }
}

enum ConnectionViewMode: String, CaseIterable, Identifiable {
    case connections = "Connections"
    case applications = "Applications"
    
    var id: String { rawValue }
}

// MARK: - View

struct ConnectionsView: View {
    @StateObject private var viewModel = ConnectionsViewModel()
    @State private var searchText = ""
    @State private var viewMode: ConnectionViewMode = .connections
    
    // Sort orders
    @State private var connectionSortOrder = [KeyPathComparator(\Connection.start, order: .reverse)]
    @State private var applicationSortOrder = [KeyPathComparator(\ApplicationStats.download, order: .reverse)]
    
    var filteredConnections: [Connection] {
        let filtered = searchText.isEmpty ? viewModel.connections : viewModel.connections.filter { conn in
            conn.metadata.host.localizedCaseInsensitiveContains(searchText) ||
            conn.metadata.destinationIP.contains(searchText) ||
            conn.rule.localizedCaseInsensitiveContains(searchText)
        }
        return filtered.sorted(using: connectionSortOrder)
    }
    
    var filteredApplications: [ApplicationStats] {
        let filtered = searchText.isEmpty ? viewModel.applications : viewModel.applications.filter { app in
            app.name.localizedCaseInsensitiveContains(searchText)
        }
        return filtered.sorted(using: applicationSortOrder)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 12) {
                // View Mode Picker
                Picker("", selection: $viewMode) {
                    ForEach(ConnectionViewMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                
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
                            Text("\(filteredApplications.count) apps")
                                .fontWeight(.medium)
                            
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down")
                                    .foregroundStyle(.blue)
                                Text(formatBytes(viewModel.totalDownload))
                            }
                            
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up")
                                    .foregroundStyle(.orange)
                                Text(formatBytes(viewModel.totalUpload))
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
                .frame(width: 250)
                
                if viewMode == .connections {
                    // Actions for Connections Mode
                    Button {
                        Task {
                            await viewModel.closeAllConnections()
                        }
                    } label: {
                        Image(systemName: "trash")
                            .fontWeight(.medium)
                    }
                    .help("Close all connections")
                    
                    Button {
                        exportConnections()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .fontWeight(.medium)
                    }
                    .help("Export connections")
                }
            }
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
        .navigationTitle("Connections")
        .task {
            await Task.yield()
            await viewModel.startMonitoring()
        }
        .onDisappear {
            viewModel.stopMonitoring()
        }
    }
    
    // MARK: - Connections Table
    private var connectionsTable: some View {
        Table(filteredConnections, sortOrder: $connectionSortOrder) {
            TableColumn("Host", value: \.metadata.host) { conn in
                let host = conn.metadata.host.isEmpty ? conn.metadata.destinationIP : conn.metadata.host
                Text(host)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.primary)
            }
            .width(min: 150, ideal: 250)
            
            // Merged Download Column
            TableColumn("Download", value: \.download) { conn in
                VStack(alignment: .leading, spacing: 2) {
                    Text(formatBytes(conn.download))
                        .font(.system(.footnote, design: .monospaced))
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    
                    if conn.downloadSpeed > 0 {
                        Text("↓ \(formatSpeed(conn.downloadSpeed))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.blue)
                    } else {
                        Text("—")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .width(ideal: 90)
            
            // Merged Upload Column
            TableColumn("Upload", value: \.upload) { conn in
                VStack(alignment: .leading, spacing: 2) {
                    Text(formatBytes(conn.upload))
                        .font(.system(.footnote, design: .monospaced))
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    
                    if conn.uploadSpeed > 0 {
                        Text("↑ \(formatSpeed(conn.uploadSpeed))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.orange)
                    } else {
                        Text("—")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .width(ideal: 90)
            
            TableColumn("Chains", value: \.chainsString) { conn in
                Text(conn.chainsString)
                    .font(.footnote)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .width(min: 150, ideal: 220)
            
            TableColumn("Rule", value: \.rule) { conn in
                VStack(alignment: .leading, spacing: 1) {
                    Text(conn.rule)
                        .font(.footnote)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    if !conn.rulePayload.isEmpty {
                        Text(conn.rulePayload)
                            .font(.system(size: 11))
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .width(ideal: 130)
            
            TableColumn("Process", value: \.processName) { conn in
                Text(conn.processName)
                    .font(.footnote)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
            }
            .width(ideal: 100)
            
            TableColumn("Time", value: \.start) { conn in
                Text(formatDuration(conn.duration))
                    .font(.footnote)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }
            .width(ideal: 70)
            
            TableColumn("Type", value: \.typeString) { conn in
                Text(conn.typeString)
                    .font(.footnote)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }
            .width(ideal: 90)
        }
        .scrollIndicators(.hidden)
    }
    
    // MARK: - Applications Table
    private var applicationsTable: some View {
        Table(filteredApplications, sortOrder: $applicationSortOrder) {
            TableColumn("Application", value: \.name) { app in
                HStack(spacing: 8) {
                    ApplicationIconView(path: app.iconPath)
                        .frame(width: 20, height: 20)
                    
                    Text(app.name)
                        .font(.system(.body))
                        .fontWeight(.medium)
                        .lineLimit(1)
                }
            }
            .width(min: 150, ideal: 250)
            
            TableColumn("Connections", value: \.connectionCount) { app in
                Text("\(app.connectionCount)")
                    .font(.footnote)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .width(ideal: 90)
            
            // Merged Download Column
            TableColumn("Download", value: \.download) { app in
                VStack(alignment: .leading, spacing: 2) {
                    Text(formatBytes(app.download))
                        .font(.system(.footnote, design: .monospaced))
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    
                    if app.downloadSpeed > 0 {
                        Text("↓ \(formatSpeed(app.downloadSpeed))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.blue)
                    } else {
                        Text("—")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .width(ideal: 100)
            
            // Merged Upload Column
            TableColumn("Upload", value: \.upload) { app in
                VStack(alignment: .leading, spacing: 2) {
                    Text(formatBytes(app.upload))
                        .font(.system(.footnote, design: .monospaced))
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    
                    if app.uploadSpeed > 0 {
                        Text("↑ \(formatSpeed(app.uploadSpeed))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.orange)
                    } else {
                        Text("—")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .width(ideal: 100)
        }
        .scrollIndicators(.hidden)
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
    
    private func processName(from path: String?) -> String {
        guard let path = path, !path.isEmpty else { return "Unknown" }
        return URL(fileURLWithPath: path).lastPathComponent
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
    @Published var applications: [ApplicationStats] = []
    
    var totalDownload: Int64 {
        applications.reduce(0) { $0 + $1.download } // or sum connections
    }
    
    var totalUpload: Int64 {
        applications.reduce(0) { $0 + $1.upload }
    }
    
    // Track previous snapshots for speed calculation
    private var previousSnapshots: [String: (up: Int64, down: Int64, time: Date)] = [:]
    private var appSnapshots: [String: (up: Int64, down: Int64, time: Date)] = [:]
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var isMonitoring = false
    
    func startMonitoring(isRetry: Bool = false) async {
        if !isRetry {
            guard !isMonitoring else { return }
            isMonitoring = true
        }
        
        // Use dynamic port based on TUN mode (port isolation)
        let tunEnabled = AppState.shared.tunEnabled
        let port = tunEnabled ? 19097 : 9097
        let url = URL(string: "ws://127.0.0.1:\(port)/connections")!
        
        // Cancel existing if any
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
            
            // Continue receiving if still monitoring
            if isMonitoring {
                await receiveMessages()
            }
        } catch {
            let nsError = error as NSError
            // Silence expected startup/shutdown errors (61: Connection Refused, 57: Socket not connected, -999: Cancelled)
            if nsError.code != 61 && nsError.code != 57 && nsError.code != -999 {
                print("[ConnectionsViewModel] ⚠️ WebSocket error: \(error.localizedDescription)")
            }
            
            // Auto-retry if still monitoring
            if isMonitoring {
                Task {
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s wait
                    await self.startMonitoring(isRetry: true)
                }
            }
        }
    }
    
    private func parseConnectionsData(_ jsonString: String) {
        // Offload heavy JSON parsing to background thread
        Task.detached(priority: .userInitiated) {
            // Get current snapshots to compare
            let oldSnapshots = await self.previousSnapshots
            let oldAppSnapshots = await self.appSnapshots
            
            // Use static method to avoid capturing 'self' during parsing
            var newConnections = Self.parseJSON(jsonString)
            let now = Date()
            
            // Process Connections & Calculate Speeds
            for i in 0..<newConnections.count {
                let conn = newConnections[i]
                if let prev = oldSnapshots[conn.id] {
                    let timeDiff = now.timeIntervalSince(prev.time)
                    if timeDiff > 0 {
                        newConnections[i].uploadSpeed = Int64(Double(conn.upload - prev.up) / timeDiff)
                        newConnections[i].downloadSpeed = Int64(Double(conn.download - prev.down) / timeDiff)
                    }
                }
            }
            
            // Aggregate Applications Data
            var appStats: [String: ApplicationStats] = [:]
            for conn in newConnections {
                let processPath = conn.metadata.processPath ?? ""
                let appName = conn.processName
                let key = processPath.isEmpty ? "Unknown" : processPath
                
                if var stats = appStats[key] {
                    stats.upload += conn.upload
                    stats.download += conn.download
                    stats.connectionCount += 1
                    appStats[key] = stats
                } else {
                    appStats[key] = ApplicationStats(
                        id: key,
                        name: appName,
                        iconPath: processPath.isEmpty ? nil : processPath,
                        upload: conn.upload,
                        download: conn.download,
                        uploadSpeed: 0,
                        downloadSpeed: 0,
                        connectionCount: 1
                    )
                }
            }
            
            var finalApps = Array(appStats.values)
            // Calculate App Speeds
            for i in 0..<finalApps.count {
                let app = finalApps[i]
                if let prev = oldAppSnapshots[app.id] {
                    let timeDiff = now.timeIntervalSince(prev.time)
                    if timeDiff > 0 {
                        finalApps[i].uploadSpeed = Int64(Double(app.upload - prev.up) / timeDiff)
                        finalApps[i].downloadSpeed = Int64(Double(app.download - prev.down) / timeDiff)
                        
                        if finalApps[i].uploadSpeed < 0 { finalApps[i].uploadSpeed = 0 }
                        if finalApps[i].downloadSpeed < 0 { finalApps[i].downloadSpeed = 0 }
                    }
                }
            }
            // Sort by total download default for stable list
            finalApps.sort { $0.download > $1.download }
            
            // Update UI on MainActor
            let finalConnections = newConnections
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    self.connections = finalConnections
                    self.applications = finalApps
                    
                    // Update snapshots for next time
                    self.previousSnapshots.removeAll()
                    for conn in finalConnections {
                        self.previousSnapshots[conn.id] = (conn.upload, conn.download, now)
                    }
                    
                    self.appSnapshots.removeAll()
                    for app in finalApps {
                        self.appSnapshots[app.id] = (app.upload, app.download, now)
                    }
                }
            }
        }
    }
    
    // Pure function for parsing, isolates logic from instance state
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
            
            // Parse start time from Clash
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
        
        do {
            let (_, _) = try await URLSession.shared.data(for: request)
            print("[ConnectionsViewModel] Closed connection: \(id)")
        } catch {
            print("[ConnectionsViewModel] Failed to close connection: \(error)")
        }
    }
    
    func closeAllConnections() async {
        let tunEnabled = AppState.shared.tunEnabled
        let port = tunEnabled ? 19097 : 9097
        guard let url = URL(string: "http://127.0.0.1:\(port)/connections") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        
        do {
            let (_, _) = try await URLSession.shared.data(for: request)
            print("[ConnectionsViewModel] Closed all connections")
        } catch {
            print("[ConnectionsViewModel] Failed to close all connections: \(error)")
        }
    }
}
