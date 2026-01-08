import SwiftUI

struct ConnectionInspectorView: View {
    let nodeID: ActivityNode.ID?
    @ObservedObject var viewModel: ConnectionsViewModel // Access data
    
    var node: ActivityNode? {
        guard let id = nodeID else { return nil }
        return findNode(id: id, nodes: viewModel.groupedNodes)
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
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Inspector")
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let node = node {
                        content(for: node)
                    } else {
                        emptyState
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 280)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    // MARK: - Content
    
    @ViewBuilder
    private func content(for node: ActivityNode) -> some View {
        // Identity Header
        VStack(alignment: .center, spacing: 8) {
            iconView(for: node)
                .frame(width: 48, height: 48)
            
            Text(node.title)
                .font(.title3)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
            
            if case .connection(let conn) = node {
                Text(conn.processName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)
        
        Divider()

        // Sections
        switch node {
        case .connection(let conn):
            connectionDetails(conn)
        case .app(let session):
            appDetails(session)
        case .group(let group):
            groupDetails(group)
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "cursorarrow.click.2")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("Select an item to inspect")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }
    
    // MARK: - Detail Sections API
    
    @ViewBuilder
    private func connectionDetails(_ conn: Connection) -> some View {
        // 1. Overview
        InfoSection("Overview") {
            InfoRow("ID", value: conn.id)
            InfoRow("Method", value: conn.typeString)
            InfoRow("Host", value: conn.metadata.host)
            InfoRow("Remote IP", value: conn.metadata.destinationIP)
            InfoRow("Remote Port", value: conn.metadata.destinationPort)
            InfoRow("Start Time", value: conn.start.formatted(date: .omitted, time: .standard))
            InfoRow("Duration", value: formatDuration(conn.duration))
        }
        
        // 2. Traffic
        InfoSection("Traffic") {
            InfoRow("Download", value: formatBytes(conn.download))
            InfoRow("Upload", value: formatBytes(conn.upload))
            InfoRow("DL Speed", value: formatSpeed(conn.downloadSpeed))
            InfoRow("UL Speed", value: formatSpeed(conn.uploadSpeed))
        }
        
        // 3. Routing (Visual Trace)
        InfoSection("Routing Trace") {
            VStack(alignment: .leading, spacing: 8) {
                if !conn.rule.isEmpty {
                    HStack {
                        Image(systemName: "list.bullet.rectangle")
                            .foregroundStyle(.purple)
                        Text(conn.rule)
                            .font(.system(.caption, design: .monospaced))
                        Spacer()
                        if !conn.rulePayload.isEmpty {
                            Text(conn.rulePayload)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                // Chain Visualization
                ForEach(Array(conn.chains.enumerated()), id: \.offset) { index, node in
                    HStack {
                        // Connector line logic
                        ZStack(alignment: .top) {
                            if index < conn.chains.count - 1 {
                                Rectangle()
                                    .fill(Color.secondary.opacity(0.3))
                                    .frame(width: 1)
                                    .padding(.top, 12)
                            }
                            Circle()
                                .fill(index == 0 ? Color.blue : Color.orange)
                                .frame(width: 8, height: 8)
                                .padding(.top, 4)
                        }
                        .frame(width: 16)
                        
                        Text(node)
                            .font(.system(.callout, design: .monospaced))
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func appDetails(_ session: AppSession) -> some View {
        InfoSection("Statistics") {
            InfoRow("Status", value: session.isRunning ? "Active" : "Terminated")
            InfoRow("Total Download", value: formatBytes(session.totalDownload))
            InfoRow("Total Upload", value: formatBytes(session.totalUpload))
            InfoRow("Active Connections", value: "\(session.activeConnections.count)")
            InfoRow("Last Active", value: session.lastActiveTime.formatted())
        }
        
        if !session.speedHistory.isEmpty {
            InfoSection("Activity Trend") {
                SparklineView(data: session.speedHistory, color: .blue)
                    .frame(height: 60)
                    .padding(.vertical, 8)
            }
        }
    }
    
    @ViewBuilder
    private func groupDetails(_ group: ActivityGroup) -> some View {
        InfoSection("Group Stats") {
            InfoRow("Title", value: group.title)
            InfoRow("Connections", value: "\(group.activeCount)")
            InfoRow("Total Download", value: formatBytes(group.download))
            InfoRow("Total Upload", value: formatBytes(group.upload))
        }
    }
    
    // MARK: - Components
    
    @ViewBuilder
    private func iconView(for node: ActivityNode) -> some View {
        if let iconPath = node.icon {
             let nsImage = NSWorkspace.shared.icon(forFile: iconPath)
             Image(nsImage: nsImage)
                 .resizable()
                 .aspectRatio(contentMode: .fit)
        } else if case .connection = node {
             Image(systemName: "globe")
                 .resizable()
                 .aspectRatio(contentMode: .fit)
                 .foregroundStyle(.blue)
        } else if case .group(let g) = node {
             Image(systemName: g.icon)
                 .resizable()
                 .aspectRatio(contentMode: .fit)
                 .foregroundStyle(.orange)
        }
    }
    
    struct InfoSection<Content: View>: View {
        let title: String
        let content: Content
        
        init(_ title: String, @ViewBuilder content: () -> Content) {
            self.title = title
            self.content = content()
        }
        
        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.footnote)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                
                VStack(alignment: .leading, spacing: 8) {
                    content
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
            }
        }
    }
    
    struct InfoRow: View {
        let label: String
        let value: String
        
        init(_ label: String, value: String) {
            self.label = label
            self.value = value
        }
        
        var body: some View {
            HStack(alignment: .top) {
                Text(label)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(width: 100, alignment: .leading)
                Text(value)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled) // Allow copying
                Spacer()
            }
        }
    }
    
    // MARK: - Formatters
    // (Duplicated for simplicity, could ensure shared availability)
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
            return String(format: "%.1fs", duration)
        } else {
            let formatter = DateComponentsFormatter()
            formatter.allowedUnits = [.hour, .minute, .second]
            formatter.unitsStyle = .abbreviated
            return formatter.string(from: duration) ?? ""
        }
    }
}
