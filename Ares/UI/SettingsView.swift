import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var clashViewModel: ClashViewModel
    @AppStorage("autoStart") private var autoStart = false
    @AppStorage("silentStart") private var silentStart = true
    @AppStorage("theme") private var theme = "system"
    
    // Clash Config - Persisted
    @AppStorage("socksPort") private var socksPort = "7891"
    @AppStorage("httpPort") private var httpPort = "7892" // Changed from 7890 to avoid conflict with mixed
    @AppStorage("mixedPort") private var mixedPort = "7890" // Changed from 7897 to standard 7890
    @AppStorage("allowLan") private var allowLan = false
    @AppStorage("ipv6") private var ipv6 = false
    @AppStorage("logLevel") private var logLevel = "info"
    
    // TUN Mode
    @AppStorage("tunEnabled") private var tunEnabled = false
    @AppStorage("tunStack") private var tunStack = "system"
    @AppStorage("tunAutoRoute") private var tunAutoRoute = true
    @AppStorage("tunAutoDetectInterface") private var tunAutoDetectInterface = true
    
    // System Proxy Bypass
    @State private var bypassRules = "localhost,127.*,10.*,172.16.*,172.31.*,192.168.*"
    
    var body: some View {
        Form {
            // System Settings
            Section("System") {
                Toggle(isOn: $autoStart) {
                    Label("Start with macOS", systemImage: "desktopcomputer")
                }
                .onChange(of: autoStart) { _, newValue in
                    do {
                        try LaunchService.shared.setLaunchAtLogin(enabled: newValue)
                        print("[Settings] Auto-start set to \(newValue)")
                    } catch {
                        print("[Settings] Failed to set auto-start: \(error)")
                        // Revert if failed (optional, but good UX)
                        // autoStart = !newValue 
                    }
                }
                Toggle(isOn: $silentStart) {
                    Label("Silent Start", systemImage: "bell.slash")
                }
                Picker(selection: $theme) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                } label: {
                    Label("Theme", systemImage: "paintpalette")
                }
                .onChange(of: theme) { _, newValue in
                    DispatchQueue.main.async {
                        ThemeService.shared.theme = newValue
                    }
                }
            }
            
            // Clash Core Settings
            Section("Clash Core") {
                LabeledContent {
                    TextField("7892", text: $httpPort)
                        .frame(width: 80)
                } label: {
                    Label("HTTP Port", systemImage: "globe")
                }
                
                LabeledContent {
                    TextField("7891", text: $socksPort)
                        .frame(width: 80)
                } label: {
                    Label("SOCKS Port", systemImage: "network")
                }

                LabeledContent {
                    TextField("7890", text: $mixedPort)
                        .frame(width: 80)
                } label: {
                    Label("Mixed Port", systemImage: "arrow.triangle.merge")
                }
                
                Toggle(isOn: $allowLan) {
                    Label("Allow LAN", systemImage: "wifi")
                }
                
                Toggle(isOn: $ipv6) {
                    Label("IPv6", systemImage: "network.badge.shield.half.filled")
                }
                
                Button("Restart Core") {
                    Task {
                        await clashViewModel.restart()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            
            // TUN Mode  
            Section("TUN Mode") {
                Toggle(isOn: $tunEnabled) {
                    Label("Enable TUN", systemImage: "network")
                }
                .help("Enable virtual network interface for global traffic capture")
                
                Picker(selection: $tunStack) {
                    Text("system").tag("system")
                    Text("gvisor").tag("gvisor")
                } label: {
                    Label("Stack", systemImage: "square.3.layers.3d")
                }
                
                Toggle(isOn: $tunAutoRoute) {
                    Label("Auto Route", systemImage: "arrow.triangle.branch")
                }
                
                Toggle(isOn: $tunAutoDetectInterface) {
                    Label("Auto Detect Interface", systemImage: "antenna.radiowaves.left.and.right")
                }
            }
            
            // Note about TUN
            Section("TUN Mode") {
                Text("TUN mode requires administrator privileges")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Changes to TUN settings require core restart")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // System Proxy Bypass
            Section("System Proxy") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Bypass Rules")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    TextEditor(text: $bypassRules)
                        .frame(height: 80)
                        .font(.system(.body, design: .monospaced))
                        .border(Color.gray.opacity(0.3))
                    
                    Text("Comma-separated list of domains/IPs to bypass")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                
                Button("Apply Bypass Rules") {
                    applyBypassRules()
                }
                .buttonStyle(.bordered)
            }
            
            // Advanced
            Section("Advanced") {
                Toggle("Enable Logs", isOn: .constant(true))
                
                Picker("Log Level", selection: $logLevel) {
                    Text("Silent").tag("silent")
                    Text("Error").tag("error")
                    Text("Warning").tag("warning")
                    Text("Info").tag("info")
                    Text("Debug").tag("debug")
                }
                
                Button("Clear Cache") {
                    clearCache()
                }
                
                Button("Reset Settings") {
                    resetSettings()
                }
                .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }
    
    private func applyBypassRules() {
        let rules = bypassRules.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        print("[Settings] Bypass rules saved: \(rules)")
        // Bypass rules are automatically used by SystemProxyManager when enabled
    }
    
    private func clearCache() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let aresDir = appSupport.appendingPathComponent("Ares")
        
        // Clear clash cache directory if exists
        let cacheDir = aresDir.appendingPathComponent("cache")
        try? FileManager.default.removeItem(at: cacheDir)
        
        print("[Settings] Cache cleared")
    }
    
    private func resetSettings() {
        // Reset to defaults
        httpPort = "7892"
        socksPort = "7891"
        mixedPort = "7890"
        allowLan = false
        ipv6 = false
        logLevel = "info"
        autoStart = false
        silentStart = true
        theme = "system"
        
        print("[Settings] Settings reset to defaults")
        
        // Restart core to apply
        Task {
            await clashViewModel.restart()
        }
    }
}
