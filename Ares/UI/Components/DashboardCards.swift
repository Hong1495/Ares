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
                    .font(.footnote)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(modeColor.opacity(0.15))
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
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.primary)
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
    @EnvironmentObject var clashViewModel: ClashViewModel
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
                                .fontWeight(.medium)
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
                print("[IpInfoCard] 🤫 Silencing IP fetch - toggling in progress")
                self.isLoading = false
                return
            }
            
            do {
                print("[IpInfoCard] Fetching IP (Attempt \(attempt))...")
                let url = URL(string: "https://ipapi.co/json/")!
                let (data, _) = try await URLSession.shared.data(from: url)
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                
                let ip = json?["ip"] as? String ?? "Unknown"
                let country = json?["country_name"] as? String
                let city = json?["city"] as? String
                
                print("[IpInfoCard] Got IP: \(ip)")
                
                self.ipInfo = IPInfo(ip: ip, country: country, city: city)
                self.isLoading = false
                return // Success
            } catch {
                if attempt == retries {
                    print("[IpInfoCard] ❌ Final attempt failed: \(error.localizedDescription)")
                }
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
            Label("Clash Core", systemImage: "gearshape.2")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Version")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(version)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
                
                HStack {
                    Text("Memory")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatMemory(memory))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
            }
        }
        .padding()
        .frame(height: 140)
        .frame(maxWidth: .infinity, alignment: .topLeading)
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
            // SILENCE during toggles to avoid "Connection refused" noise
            if clashViewModel.isToggling {
                self.version = "Toggling..."
                return
            }
            
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                
                if let versionStr = json?["version"] as? String {
                    self.version = versionStr
                    return // Success
                }
            } catch {
                if attempt == retries {
                    print("[ClashInfoCard] ❌ Final attempt failed: \(error.localizedDescription)")
                }
                if attempt < retries {
                    try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s
                }
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
            Label("System", systemImage: "cpu")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("macOS")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(osVersion)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
                
                HStack {
                    Text("Architecture")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(architecture)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
            }
        }
        .padding()
        .frame(height: 140)
        .frame(maxWidth: .infinity, alignment: .topLeading)
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
            
            // Get OS version
            let version = ProcessInfo.processInfo.operatingSystemVersion
            osVersion = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        }
    }
}
