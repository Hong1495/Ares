import SwiftUI

// Current Proxy Card - Shows active proxy selections
struct CurrentProxyCard: View {
    @EnvironmentObject var clashController: ClashController
    @EnvironmentObject var appState: AppState
    
    // Display groups based on mode
    var displayGroups: [ProxyGroup] {
        switch appState.currentMode {
        case .global:
            return clashController.proxyGroups.filter { $0.name == "GLOBAL" }
        case .direct:
            return []
        case .rule:
            // Rule mode: ONLY show 节点选择
            return clashController.proxyGroups.filter { $0.name == "🚀 节点选择" }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Current Proxy", systemImage: "network")
                    .font(.headline)
                Spacer()
                // Mode indicator
                Text(appState.currentMode.rawValue.capitalized)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(modeColor.opacity(0.2))
                    .foregroundStyle(modeColor)
                    .cornerRadius(6)
            }
            
            Divider()
            
            if appState.currentMode == .direct {
                // Direct mode
                HStack {
                    Image(systemName: "arrow.forward.circle")
                        .foregroundStyle(.green)
                    Text("Direct Connection")
                        .font(.subheadline)
                    Spacer()
                }
            } else if displayGroups.isEmpty {
                Text("No proxy configured")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                // Show groups
                ForEach(displayGroups) { group in
                    HStack {
                        Image(systemName: groupIcon(for: group.type))
                            .foregroundStyle(.blue)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.name)
                                .font(.subheadline)
                            if let current = group.now {
                                Text(current)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
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
        default: return "network"
        }
    }
}

/// IP Info Card showing public IP information
struct IpInfoCard: View {
    @State private var ipInfo: IPInfo?
    @State private var isLoading = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("IP Address", systemImage: "globe")
                    .font(.headline)
                Spacer()
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
            
            if let info = ipInfo {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "network")
                            .foregroundStyle(.blue)
                        Text(info.ip)
                            .font(.system(.body, design: .monospaced))
                    }
                    
                    if let country = info.country {
                        HStack {
                            Image(systemName: "location")
                                .foregroundStyle(.green)
                            Text(country)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                Text("Fetching IP info...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(height: 140)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .onAppear {
            Task {
                await fetchIPInfo()
            }
        }
    }
    
    private func fetchIPInfo() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            print("[IpInfoCard] Fetching IP...")
            // Use ipapi.co which supports HTTPS and returns all info in one request
            let url = URL(string: "https://ipapi.co/json/")!
            let (data, _) = try await URLSession.shared.data(from: url)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            
            let ip = json?["ip"] as? String ?? "Unknown"
            let country = json?["country_name"] as? String
            let city = json?["city"] as? String
            
            print("[IpInfoCard] Got IP: \(ip), Location: \(country ?? "N/A"), \(city ?? "N/A")")
            
            await MainActor.run {
                ipInfo = IPInfo(ip: ip, country: country, city: city)
            }
        } catch {
            print("[IpInfoCard] Error: \(error)")
        }
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
            Label("Clash Core", systemImage: "gearshape.2")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Version")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(version)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                
                HStack {
                    Text("Memory")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatMemory(memory))
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }
        }
        .padding()
        .frame(height: 140)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .onAppear {
            Task {
                await fetchClashInfo()
            }
        }
    }
    
    private func fetchClashInfo() async {
        do {
            let url = URL(string: "http://127.0.0.1:9097/version")!
            let (data, _) = try await URLSession.shared.data(from: url)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            
            print("[ClashInfoCard] API Response: \(json ?? [:])")
            
            if let versionStr = json?["version"] as? String {
                await MainActor.run {
                    version = versionStr
                }
            }
            
            // Note: Clash API doesn't return memory in /version endpoint
            // We'd need to use /memory or另一个 endpoint for that
        } catch {
            print("[ClashInfoCard] Error: \(error)")
            await MainActor.run {
                version = "API Error"
            }
        }
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
            Label("System", systemImage: "cpu")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("macOS")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(osVersion)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                
                HStack {
                    Text("Architecture")
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
        .frame(height: 140)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .onAppear {
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
        architecture = machine
        
        // Get OS version
        let version = ProcessInfo.processInfo.operatingSystemVersion
        osVersion = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
}
