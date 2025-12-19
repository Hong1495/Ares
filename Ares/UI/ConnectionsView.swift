import SwiftUI
import Combine
import UniformTypeIdentifiers

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

/// Connections View
struct ConnectionsView: View {
    @StateObject private var viewModel = ConnectionsViewModel()
    @State private var searchText = ""
    @State private var sortOrder = [KeyPathComparator(\Connection.start, order: .reverse)]
    
    var filteredConnections: [Connection] {
        let filtered = searchText.isEmpty ? viewModel.connections : viewModel.connections.filter { conn in
            conn.metadata.host.localizedCaseInsensitiveContains(searchText) ||
            conn.metadata.destinationIP.contains(searchText) ||
            conn.rule.localizedCaseInsensitiveContains(searchText)
        }
        return filtered.sorted(using: sortOrder)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 12) {
                Text("\(filteredConnections.count) connections")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search connections...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(6)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
                .frame(width: 250)
                
                // Close All / Clear button
                Button {
                    Task {
                        await viewModel.closeAllConnections()
                    }
                } label: {
                    Image(systemName: "trash")
                }
                .help("Close all connections")
                
                // Export button
                Button {
                    exportConnections()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .help("Export connections")
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // Native Table
            Table(filteredConnections, sortOrder: $sortOrder) {
                TableColumn("Host", value: \.metadata.host) { conn in
                    let host = conn.metadata.host.isEmpty ? conn.metadata.destinationIP : conn.metadata.host
                    Text(host)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.primary)
                }
                .width(min: 150, ideal: 250)
                
                TableColumn("Traffic", value: \.download) { conn in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.blue)
                            Text(formatBytes(conn.download))
                        }
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.orange)
                            Text(formatBytes(conn.upload))
                        }
                    }
                    .font(.system(.caption, design: .monospaced))
                }
                .width(ideal: 110)
                
                TableColumn("Speed", value: \.downloadSpeed) { conn in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("↓ \(formatSpeed(conn.downloadSpeed))").foregroundStyle(.blue)
                        Text("↑ \(formatSpeed(conn.uploadSpeed))").foregroundStyle(.orange)
                    }
                    .font(.system(.caption, design: .monospaced))
                }
                .width(ideal: 110)
                
                TableColumn("Chains", value: \.chainsString) { conn in
                    Text(conn.chainsString)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .width(min: 150, ideal: 220)
                
                TableColumn("Rule", value: \.rule) { conn in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(conn.rule)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                        if !conn.rulePayload.isEmpty {
                            Text(conn.rulePayload)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .width(ideal: 130)
                
                TableColumn("Process", value: \.processName) { conn in
                    Text(conn.processName)
                        .font(.caption)
                        .foregroundStyle(.primary)
                }
                .width(ideal: 100)
                
                TableColumn("Time", value: \.start) { conn in
                    Text(formatDuration(conn.duration))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .width(ideal: 70)
                
                TableColumn("Source", value: \.sourceString) { conn in
                    Text(conn.sourceString)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .width(ideal: 140)
                
                TableColumn("Destination", value: \.destinationString) { conn in
                    Text(conn.destinationString)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .width(ideal: 140)
                
                TableColumn("Type", value: \.typeString) { conn in
                    Text(conn.typeString)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .width(ideal: 90)
            }
        }
        .navigationTitle("Connections")
        .onAppear {
            Task {
                await viewModel.startMonitoring()
            }
        }
        .onDisappear {
            viewModel.stopMonitoring()
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

// Deleted ConnectionRow [NATIVE TABLE REPLACEMENT]


/// ViewModel for Connections
@MainActor
final class ConnectionsViewModel: ObservableObject {
    @Published var connections: [Connection] = []
    
    // Track previous snapshots for speed calculation
    private var previousSnapshots: [String: (up: Int64, down: Int64, time: Date)] = [:]
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var isMonitoring = false
    
    func startMonitoring() async {
        guard !isMonitoring else { return }
        isMonitoring = true
        
        // Use dynamic port based on TUN mode (port isolation)
        let tunEnabled = AppState.shared.tunEnabled
        let port = tunEnabled ? 19097 : 9097
        let url = URL(string: "ws://127.0.0.1:\(port)/connections")!
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
            print("[ConnectionsViewModel] WebSocket error: \(error)")
            isMonitoring = false
        }
    }
    
    private func parseConnectionsData(_ jsonString: String) {
        // Offload heavy JSON parsing to background thread
        Task.detached(priority: .userInitiated) {
            // Get current snapshots to compare
            let oldSnapshots = await self.previousSnapshots
            
            // Use static method to avoid capturing 'self' during parsing
            var newConnections = Self.parseJSON(jsonString)
            let now = Date()
            
            // Calculate speeds
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
            
                // Update UI on MainActor
                let finalConnections = newConnections
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    self.connections = finalConnections
                    
                    // Update snapshots for next time
                    self.previousSnapshots.removeAll()
                    for conn in finalConnections {
                        self.previousSnapshots[conn.id] = (conn.upload, conn.download, now)
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
