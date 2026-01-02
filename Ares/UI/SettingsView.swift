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
    
    // MITM Settings
    @AppStorage("mitmPorts") private var mitmPorts = "80, 443, 8080, 8443"
    @AppStorage("mitmHosts") private var mitmHosts = ""  // Empty = intercept all hosts
    @AppStorage("tlsFingerprint") private var tlsFingerprint = "none"
    
    var body: some View {
        Form {
            // General Settings
            Section("General") {
                Toggle(isOn: $autoStart) {
                    Label("Start with macOS", systemImage: "macwindow")
                        .fontWeight(.medium)
                }
                .onChange(of: autoStart) { _, newValue in
                    Task {
                        try? LaunchService.shared.setLaunchAtLogin(enabled: newValue)
                    }
                }
                
                Toggle(isOn: $silentStart) {
                    Label("Silent Start", systemImage: "bell.slash")
                        .fontWeight(.medium)
                }
                
                Picker(selection: $theme) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                } label: {
                    Label("Theme", systemImage: "paintpalette")
                        .fontWeight(.medium)
                }
                .onChange(of: theme) { _, newValue in
                    Task { @MainActor in
                        ThemeService.shared.theme = newValue
                    }
                }
            }
            
            // Core Networking
            Section("Clash Core") {
                LabeledContent {
                    TextField("", text: $httpPort)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                } label: {
                    Text("HTTP Port")
                        .fontWeight(.medium)
                }
                
                LabeledContent {
                    TextField("", text: $socksPort)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                } label: {
                    Text("SOCKS Port")
                        .fontWeight(.medium)
                }

                LabeledContent {
                    TextField("", text: $mixedPort)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                } label: {
                    Text("Mixed Port")
                        .fontWeight(.medium)
                }
                
                Toggle(isOn: $allowLan) {
                    Text("Allow LAN")
                        .fontWeight(.medium)
                }
                Toggle(isOn: $ipv6) {
                    Text("IPv6 Support")
                        .fontWeight(.medium)
                }
                
                Button("Restart Clash Core") {
                    Task {
                        await clashViewModel.restart()
                    }
                }
                .buttonStyle(.bordered)
            }
            
            // Unified TUN Mode Info
            Section {
                Toggle(isOn: $tunEnabled) {
                    Text("Enable TUN Support")
                        .fontWeight(.medium)
                }
                
                Picker("Network Stack", selection: $tunStack) {
                    Text("System").tag("system")
                    Text("gVisor").tag("gvisor")
                }
                .disabled(!tunEnabled)
                
                Toggle(isOn: $tunAutoRoute) {
                    Text("Auto Route")
                        .fontWeight(.medium)
                }
                    .disabled(!tunEnabled)
                
                Toggle(isOn: $tunAutoDetectInterface) {
                    Text("Auto Detect Interface")
                        .fontWeight(.medium)
                }
                    .disabled(!tunEnabled)
            } header: {
                Label("TUN Mode", systemImage: "bolt.shield")
                    .fontWeight(.medium)
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("• Requires administrator privileges")
                    Text("• Global traffic capture via virtual interface")
                    Text("• Changes require core restart")
                }
                .font(.footnote)
                .fontWeight(.medium)
            }
            
            // System Proxy Bypass
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Bypass Domains")
                        .fontWeight(.medium)
                    TextEditor(text: $bypassRules)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 100)
                        .padding(4)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(4)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.2)))
                        .scrollIndicators(.hidden)
                    
                    Text("Comma-separated domains/IPs to bypass proxy")
                        .font(.footnote)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("MITM Intercept Ports")
                        .fontWeight(.medium)
                    TextField("Ports", text: $mitmPorts)
                        .textFieldStyle(.roundedBorder)
                    
                    Text("Comma-separated ports to intercept (e.g. 80, 443, 8888)")
                        .font(.footnote)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("MITM Host Whitelist")
                        .fontWeight(.medium)
                    TextField("Hosts (empty = all)", text: $mitmHosts)
                        .textFieldStyle(.roundedBorder)
                    
                    Text("Comma-separated hosts/IPs to intercept (e.g. 10.10.25.251, api.example.com)")
                        .font(.footnote)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)


                
                Button("Apply Proxy Rules") {
                    Task {
                        // 0. Refresh MITM Backend whitelist (for display filtering and connection bypass)
                        await MITMBackend.shared.refreshDisplayWhitelist()
                        
                        // 1. Refresh system proxy with new rules if currently enabled
                        if appState.systemProxyEnabled {
                            await appState.toggleSystemProxy() // Off
                            await appState.toggleSystemProxy() // On with new rules
                        }
                        
                        // 2. If TUN mode is active, we MUST restart Clash to rebuild config with new MITM domain rules
                        if tunEnabled {
                            let wasMITMRunning = NetworkMITMService.shared.isRunning
                            
                            // Stop MITM first to prevent errors during Clash restart
                            if wasMITMRunning {
                                await NetworkMITMService.shared.stop()
                            }
                            
                            await clashViewModel.restart()
                            
                            // Restart MITM if it was running (with safety delay)
                            if wasMITMRunning {
                                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s wait for Core stability
                                await NetworkMITMService.shared.start()
                            }
                        }
                        
                        clashViewModel.addLog("[Settings] ✅ Proxy rules applied")
                    }
                }
                .buttonStyle(.bordered)
            }
            
            // Advanced Features
            Section("Advanced") {
                Picker("TLS Fingerprint", selection: $tlsFingerprint) {
                    Text("Disabled (Default)").tag("none")
                    Text("Chrome (Recommended)").tag("chrome")
                    Text("Safari (iOS)").tag("ios")
                    Text("Firefox").tag("firefox")
                    Text("Randomized").tag("random")
                }
                .pickerStyle(.menu)
                .onChange(of: tlsFingerprint) { _, _ in
                    Task {
                        await clashViewModel.restart()
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mimic browser fingerprints to bypass Deep Packet Inspection (DPI).")
                    Text("• Helps reduce connection drops and throttling")
                    Text("• Applies to supported proxy protocols automatically")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
            }
            
            // Other & Maintenance
            Section("Other") {
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
        .scrollIndicators(.hidden)
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
