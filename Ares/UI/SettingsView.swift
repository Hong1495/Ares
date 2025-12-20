import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var clashViewModel: ClashViewModel
    @EnvironmentObject var appState: AppState
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
    @AppStorage("bypassRules") private var bypassRules = "localhost,127.*,10.*,172.16.*,172.31.*,192.168.*"
    
    var body: some View {
        Form {
            // General Settings
            Section("General") {
                Toggle(isOn: $autoStart) {
                    Label("Start with macOS", systemImage: "desktopcomputer")
                }
                .onChange(of: autoStart) { _, newValue in
                    Task {
                        try? LaunchService.shared.setLaunchAtLogin(enabled: newValue)
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
                    Task { @MainActor in
                        ThemeService.shared.theme = newValue
                    }
                }
            }
            
            // Core Networking
            Section("Clash Core") {
                LabeledContent("HTTP Port") {
                    TextField("7892", text: $httpPort)
                        .frame(width: 60)
                }
                
                LabeledContent("SOCKS Port") {
                    TextField("7891", text: $socksPort)
                        .frame(width: 60)
                }

                LabeledContent("Mixed Port") {
                    TextField("7890", text: $mixedPort)
                        .frame(width: 60)
                }
                
                Toggle("Allow LAN", isOn: $allowLan)
                Toggle("IPv6 Support", isOn: $ipv6)
                
                Button("Restart Clash Core") {
                    Task {
                        await clashViewModel.restart()
                    }
                }
                .buttonStyle(.bordered)
            }
            
            // Unified TUN Mode Info
            Section {
                Toggle("Enable TUN Mode", isOn: $tunEnabled)
                
                Picker("Network Stack", selection: $tunStack) {
                    Text("System").tag("system")
                    Text("gVisor").tag("gvisor")
                }
                .disabled(!tunEnabled)
                
                Toggle("Auto Route", isOn: $tunAutoRoute)
                    .disabled(!tunEnabled)
                
                Toggle("Auto Detect Interface", isOn: $tunAutoDetectInterface)
                    .disabled(!tunEnabled)
            } header: {
                Text("TUN Mode")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("• Requires administrator privileges")
                    Text("• Global traffic capture via virtual interface")
                    Text("• Changes require core restart")
                }
                .font(.caption2)
            }
            
            // System Proxy Bypass
            Section("System Proxy Bypass") {
                VStack(alignment: .leading, spacing: 8) {
                    TextEditor(text: $bypassRules)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 100)
                        .padding(4)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(4)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.2)))
                    
                    Text("Comma-separated domains/IPs to bypass proxy")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                
                Button("Apply Proxy Rules") {
                    Task {
                        // Refresh system proxy with new rules if currently enabled
                        if appState.systemProxyEnabled {
                            await appState.toggleSystemProxy() // Off
                            await appState.toggleSystemProxy() // On with new rules
                        }
                    }
                }
                .buttonStyle(.bordered)
            }
            
            // Advanced & Maintenance
            Section("Advanced") {
                Picker("Log Level", selection: $logLevel) {
                    Text("Silent").tag("silent")
                    Text("Error").tag("error")
                    Text("Warning").tag("warning")
                    Text("Info").tag("info")
                    Text("Debug").tag("debug")
                }
                .onChange(of: logLevel) { _, newValue in
                    Task {
                        try? await ClashController.shared.setLogLevel(newValue)
                    }
                }
                
                HStack {
                    Button("Clear Cache") {
                        clearCache()
                    }
                    Spacer()
                    Button("Reset to Defaults") {
                        resetSettings()
                    }
                    .foregroundStyle(.red)
                }
                .buttonStyle(.bordered)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }
    
    private func clearCache() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let cacheDir = appSupport.appendingPathComponent("Ares/cache")
        try? FileManager.default.removeItem(at: cacheDir)
        print("[Settings] Cache cleared")
    }
    
    private func resetSettings() {
        httpPort = "7892"
        socksPort = "7891"
        mixedPort = "7890"
        allowLan = false
        ipv6 = false
        logLevel = "info"
        autoStart = false
        silentStart = true
        theme = "system"
        bypassRules = "localhost,127.*,10.*,172.16.*,172.31.*,192.168.*"
        
        Task {
            await clashViewModel.restart()
        }
    }
}
