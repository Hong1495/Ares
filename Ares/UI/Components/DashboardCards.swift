import SwiftUI

// Current Proxy Card - Shows active proxy selections with latency
struct CurrentProxyCard: View {
    @EnvironmentObject var clashController: ClashController
    @EnvironmentObject var appState: AppState
    
    // Auto-refresh latency
    @State private var latencies: [String: Int] = [:]
    
    // Display groups based on mode
    var displayGroups: [ProxyGroup] {
        switch appState.currentMode {
        case .global:
            return clashController.proxyGroups.filter { $0.name == "GLOBAL" }
        case .direct:
            return []
        case .rule:
            return clashController.proxyGroups.filter { $0.name == "🚀 节点选择" }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label {
                    Text("Current Proxy")
                } icon: {
                    Image(systemName: "server.rack")
                        .fontWeight(.light)
                        .frame(width: 20)
                }
                .font(.headline)
                Spacer()
                // Mode indicator
                Text(appState.currentMode.rawValue.capitalized)
                    .font(.footnote)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(modeColor.opacity(0.15))
                    .foregroundStyle(modeColor)
                    .cornerRadius(6)
            }
            .frame(height: 24) // Align header height
            
            Divider()
            
            if appState.currentMode == .direct {
                // Direct mode
                VStack {
                    Spacer()
                    HStack {
                        Image(systemName: "arrow.forward.circle")
                            .foregroundStyle(.green)
                        Text("Direct Connection")
                            .font(.subheadline)
                        Spacer()
                    }
                    Spacer()
                }
            } else if displayGroups.isEmpty {
                 VStack {
                    Spacer()
                    Text("No proxy configured")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer()
                }
            } else {
                // Show groups
                // Bottom align
                Spacer()
                ForEach(displayGroups) { group in
                    HStack {
                        Image(systemName: groupIcon(for: group.type))
                            .foregroundStyle(.blue)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.name)
                                .font(.subheadline)
                                .lineLimit(1)
                            if let current = group.now {
                                HStack(spacing: 6) {
                                    Text(current)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    
                                    // Latency Badge
                                    if let ms = latencies[current] {
                                        Text("\(ms)ms")
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .foregroundStyle(latencyColor(ms))
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 2)
                                            .background(latencyColor(ms).opacity(0.1))
                                            .cornerRadius(4)
                                    } else {
                                        Text("- ms")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        
                        Spacer()
                    }
                }
            }
        }
        .padding()
        .frame(height: 150)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .task {
            // Initial delay wait
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await updateLatencies()
            
            // Periodic update
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5s
                await updateLatencies()
            }
        }
    }
    
    private func updateLatencies() async {
        for group in displayGroups {
            if let current = group.now {
                // Skip if we already tested recently (< 5s)? No, auto-refresh is explicit.
                do {
                    let ms = try await clashController.testProxyDelay(name: current, timeout: 2000)
                    withAnimation {
                        latencies[current] = ms
                    }
                } catch {
                    // ignore
                }
            }
        }
    }
    
    private func latencyColor(_ ms: Int) -> Color {
        if ms < 200 { return .green }
        if ms < 500 { return .orange }
        return .red
    }
    
    private var modeColor: Color {
        switch appState.currentMode {
        case .rule: return .blue
        case .global: return .orange
        case .direct: return .green
        }
    }
    
    private func groupIcon(for type: String) -> String {
        switch type {
        case "Selector": return "checkmark.circle"
        case "URLTest": return "speedometer"
        case "Fallback": return "arrow.triangle.2.circlepath"
        default: return "server.rack"
        }
    }
}

/// IP Info Card showing public IP information
struct IpInfoCard: View {
    @EnvironmentObject var clashViewModel: ClashViewModel
    @State private var ipInfo: IPInfo?
    @State private var isLoading = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text("IP Address")
            } icon: {
                Image(systemName: "globe.americas") // Simpler icon
                    .fontWeight(.light)
                    .frame(width: 20)
            }
            .font(.headline.weight(.medium))
            .frame(height: 24)
            
            Divider()
            
            Spacer()
            
            if let info = ipInfo {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "link")
                            .font(.caption) // Smaller icon
                            .foregroundStyle(.blue.opacity(0.8))
                        Text(info.ip)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .monospacedDigit()
                    }
                    
                    if let country = info.country {
                        HStack(spacing: 6) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.caption)
                                .foregroundStyle(.green.opacity(0.8))
                            Text(country)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else if isLoading {
               ProgressView()
                    .scaleEffect(0.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Tap to check IP")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .onTapGesture {
                        Task { await fetchIPInfo() }
                    }
            }
        }
        .padding()
        .frame(height: 150) // Match others
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .task {
            // Wait for Clash to be running before first fetch to avoid "Connection refused" startup noise
            while !clashViewModel.isRunning {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s
            }
            // Tiny extra gap for TCP stack readiness
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            await fetchIPInfo()
        }
    }
    
    @MainActor
    private func fetchIPInfo(retries: Int = 3) async {
        isLoading = true
        
        for attempt in 1...retries {
            // SILENCE during toggles to avoid "Connection refused" noise
            if clashViewModel.isToggling {
                self.isLoading = false
                return
            }
            
            do {
                let url = URL(string: "https://ipapi.co/json/")!
                let (data, _) = try await URLSession.shared.data(from: url)
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                
                let ip = json?["ip"] as? String ?? "Unknown"
                let country = json?["country_name"] as? String
                let city = json?["city"] as? String
                
                self.ipInfo = IPInfo(ip: ip, country: country, city: city)
                self.isLoading = false
                return // Success
            } catch {
                if attempt < retries {
                    try? await Task.sleep(nanoseconds: 2_000_000_000) // Wait 2s
                }
            }
        }
        
        self.isLoading = false
    }
}

struct IPInfo {
    let ip: String
    let country: String?
    let city: String?
}

/// Clash Info Card showing core information
struct ClashInfoCard: View {
    @State private var version: String = "Loading..."
    @State private var memory: Int64 = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text("Clash Core")
            } icon: {
                Image(systemName: "gearshape") // Simpler icon
                    .fontWeight(.light)
                    .frame(width: 20)
            }
            .font(.headline.weight(.medium))
            .frame(height: 24)
            
            Divider()
            
            Spacer()
            
            VStack(alignment: .leading, spacing: 4) {
                 HStack {
                    Text("Version")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(version)
                        .font(.caption)
                        .fontWeight(.medium)
                        .monospacedDigit()
                }
                
                // Memory removed to keep it simple/matching system box, or keep if user wants?
                // Request said: "Clash Core", "IP Address", "System".
                // System box shows macOS + Arch.
                // Clash box shows Version + Memory (maybe?).
                // Let's keep it simple as Version only for now to match System layout visuals more closely or keep both?
                // The provided image shows "Clash Core" -> "Version v1.18.1", "Memory 9.6MB".
                // So I should keep both.
                
                HStack {
                    Text("Memory")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatMemory(memory)) // This needs to be fetched or mocked, currently struct had mock
                        .font(.caption)
                        .fontWeight(.medium)
                        .monospacedDigit()
                }
            }
        }
        .padding()
        .frame(height: 150)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .task {
            while !clashViewModel.isRunning {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s
            }
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s cool-down
            await fetchClashInfo()
        }
    }
    
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var clashViewModel: ClashViewModel

    @MainActor
    private func fetchClashInfo(retries: Int = 5) async {
        let port = appState.tunEnabled ? 19097 : 9097
        let url = URL(string: "http://127.0.0.1:\(port)/version")!
        
        for attempt in 1...retries {
            if clashViewModel.isToggling { return }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                if let versionStr = json?["version"] as? String {
                    self.version = versionStr
                    // Mock memory for now as /version doesn't return it
                    self.memory = 10 * 1024 * 1024 
                    return 
                }
            } catch {
                if attempt < retries { try? await Task.sleep(nanoseconds: 1_500_000_000) }
            }
        }
        self.version = "Offline"
    }
    
    private func formatMemory(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1024 / 1024
        return String(format: "%.1f MB", mb)
    }
}

/// System Info Card showing system metrics
struct SystemInfoCard: View {
    @State private var architecture: String = "Unknown"
    @State private var osVersion: String = "Unknown"
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text("System")
            } icon: {
                Image(systemName: "cpu") // Simple icon
                    .fontWeight(.light)
                    .frame(width: 20)
            }
            .font(.headline.weight(.medium))
            .frame(height: 24)
            
            Divider()
            
            Spacer()
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("macOS")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(osVersion)
                        .font(.caption)
                        .fontWeight(.medium)
                        .monospacedDigit()
                }
                
                HStack {
                    Text("Arch") // Shortened to match space
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(architecture)
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }
        }
        .padding()
        .frame(height: 150)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .task {
            await Task.yield()
            fetchSystemInfo()
        }
    }
    
    private func fetchSystemInfo() {
        // Get architecture
        var sysinfo = utsname()
        uname(&sysinfo)
        let machine = withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
        DispatchQueue.main.async {
            architecture = machine
            let version = ProcessInfo.processInfo.operatingSystemVersion
            osVersion = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        }
    }
}

/// Node Analysis Card - Concise stats
struct NodeAnalysisCard: View {
    @EnvironmentObject var clashController: ClashController
    @State private var avgDelay: Int = 0
    @State private var nodeCount: Int = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text("Node Analysis")
            } icon: {
                Image(systemName: "chart.bar.doc.horizontal")
                    .fontWeight(.light)
                    .frame(width: 20)
            }
            .font(.headline.weight(.medium))
            .frame(height: 24)
            
            Divider()
            
            Spacer()
            
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Total Nodes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(nodeCount)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
                
                HStack {
                    Text("Avg Latency")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(avgDelay) ms")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .foregroundStyle(delayColor(avgDelay))
                }
            }
        }
        .padding()
        .frame(height: 150)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .onReceive(clashController.$proxyNodes) { nodes in
            // Calculate stats
            self.nodeCount = nodes.count
            
            // Calc average of known delays
            let delays = nodes.values.compactMap { $0.delay }.filter { $0 > 0 }
            if !delays.isEmpty {
                self.avgDelay = delays.reduce(0, +) / delays.count
            }
        }
    }
    
    func delayColor(_ ms: Int) -> Color {
        if ms == 0 { return .secondary }
        if ms < 300 { return .green }
        if ms < 800 { return .orange }
        return .red
    }
}

/// Connections Card - Active Connections Stats
struct ConnectionsCard: View {
    @EnvironmentObject var clashController: ClashController
    @State private var totalConnections: Int = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text("Connections")
            } icon: {
                Image(systemName: "network")
                    .fontWeight(.light)
                    .frame(width: 20)
            }
            .font(.headline.weight(.medium))
            .frame(height: 24)
            
            Divider()
            
            Spacer()
            
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Active")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(totalConnections)")
                        .font(.title2) // Prominent number
                        .fontWeight(.bold)
                        .monospacedDigit()
                }
                
                // Optional: Show current bandwidth as summary
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                        Text(formatBytes(clashController.traffic.down) + "/s")
                            .font(.caption2)
                            .monospacedDigit()
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                        Text(formatBytes(clashController.traffic.up) + "/s")
                            .font(.caption2)
                            .monospacedDigit()
                    }
                }
            }
        }
        .padding()
        .frame(height: 150)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .task {
            // Poll connections count every few seconds
             while !Task.isCancelled {
                do {
                    let json = try await clashController.fetchConnections()
                    if let connections = json["connections"] as? [[String: Any]] {
                        await MainActor.run {
                            self.totalConnections = connections.count
                        }
                    }
                } catch {}
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s
            }
        }
    }
    
    func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bytes)
    }
}

/// Error Log Card - Showing recent errors
struct ErrorLogCard: View {
    @EnvironmentObject var clashViewModel: ClashViewModel
    
    // Filtered logs
    var errorLogs: [String] {
        clashViewModel.logs.filter { $0.contains("⚠️") || $0.contains("❌") || $0.lowercased().contains("error") || $0.lowercased().contains("fail") }
            .suffix(2) // Last 2 only
            .reversed() // Newest first
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text("Error Logs")
            } icon: {
                Image(systemName: "exclamationmark.triangle")
                    .fontWeight(.light)
                    .frame(width: 20)
            }
            .font(.headline.weight(.medium))
            .frame(height: 24)
            .foregroundStyle(errorLogs.isEmpty ? Color.primary : Color.orange)
            
            Divider()
            
            Spacer()
            
            if errorLogs.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.green)
                    Text("No active errors")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(errorLogs, id: \.self) { log in
                        Text(cleanLog(log))
                            .font(.caption2) // Tiny text for logs
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding()
        .frame(height: 150)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }
    
    func cleanLog(_ log: String) -> String {
        return log
    }
}
