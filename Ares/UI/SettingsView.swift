import SwiftUI
import AppKit

// MARK: - Pane model

/// Five-pane split of what used to be one endless Form.
private enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case network
    case tun
    case mitm
    case rules

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .network: return "Network"
        case .tun: return "TUN"
        case .mitm: return "MITM"
        case .rules: return "Rules"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .network: return "network"
        case .tun: return "bolt.shield"
        case .mitm: return "lock.shield"
        case .rules: return "list.bullet.rectangle"
        }
    }
}

// MARK: - Row style

/// Label left, control flush right — the alignment `LabeledContent` only gets
/// for free inside a `Form`, which this screen no longer uses.
private struct SettingRowStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: DS.Space.md) {
            configuration.label
                .font(DS.Typography.body.weight(.medium))
            Spacer(minLength: DS.Space.md)
            configuration.content
        }
        .frame(minHeight: 22)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - View

struct SettingsView: View {
    @ObservedObject private var appUpdates = AppUpdateService.shared
    @EnvironmentObject var clashViewModel: ClashViewModel
    @EnvironmentObject var appState: AppState
    @AppStorage(DefaultsKeys.autoStart) private var autoStart = false
    @AppStorage(DefaultsKeys.silentStart) private var silentStart = true
    @AppStorage(DefaultsKeys.theme) private var theme = "system"
    @AppStorage(DefaultsKeys.menuBarShowsLatency) private var menuBarShowsLatency = false

    // Debounce task for auto-applying Custom Routing Rules
    @State private var localRulesRestartTask: Task<Void, Never>?

    // Clash Config - Persisted
    @AppStorage(DefaultsKeys.socksPort) private var socksPort = "\(ClashPorts.defaultSocks)"
    @AppStorage(DefaultsKeys.httpPort) private var httpPort = "\(ClashPorts.defaultHttp)" // Changed from 7890 to avoid conflict with mixed
    @AppStorage(DefaultsKeys.mixedPort) private var mixedPort = "\(ClashPorts.defaultMixed)" // Changed from 7897 to standard 7890
    @AppStorage(DefaultsKeys.allowLan) private var allowLan = false
    @AppStorage(DefaultsKeys.ipv6) private var ipv6 = false
    @AppStorage(DefaultsKeys.logLevel) private var logLevel = "info"
    @AppStorage(DefaultsKeys.dnsServers) private var dnsServers = "223.5.5.5, 119.29.29.29"

    // TUN Mode
    @AppStorage(DefaultsKeys.tunStack) private var tunStack = "system"
    @AppStorage(DefaultsKeys.tunMTU) private var tunMTU = 1400
    @AppStorage(DefaultsKeys.tunDevice) private var tunDevice = ""
    @AppStorage(DefaultsKeys.tunAutoRoute) private var tunAutoRoute = true
    @AppStorage(DefaultsKeys.tunAutoDetectInterface) private var tunAutoDetectInterface = true
    @AppStorage(DefaultsKeys.keepAliveInterval) private var keepAliveInterval = 15
    @AppStorage(DefaultsKeys.udpTimeout) private var udpTimeout = 120

    // System Proxy Bypass
    @AppStorage(DefaultsKeys.bypassRules) private var bypassRules = "localhost,127.*,10.*,172.16.*,172.31.*,192.168.*"

    // Custom Routing Rules (highest priority, injected at top of `rules:` — survives subscription updates)
    @AppStorage(DefaultsKeys.localRules) private var localRules = ""

    // MITM Settings
    @ObservedObject private var certManager = CertificateManager.shared
    @AppStorage(DefaultsKeys.mitmPorts) private var mitmPorts = "80, 443, 8080, 8443"
    @AppStorage(DefaultsKeys.mitmHosts) private var mitmHosts = ""  // Empty = intercept all hosts
    @AppStorage(DefaultsKeys.tlsFingerprint) private var tlsFingerprint = "none"

    @State private var pane: SettingsPane = .general

    private var tunEnabled: Bool { appState.tunEnabled }

    var body: some View {
        VStack(spacing: 0) {
            DSPageTabs(titles: SettingsPane.allCases.map(\.title), selection: Binding(
                get: { SettingsPane.allCases.firstIndex(of: pane) ?? 0 },
                set: { pane = SettingsPane.allCases[$0] }
            ))
            .padding(.horizontal, 30)
            .padding(.bottom, 12)
            paneDetail
        }
        .navigationTitle("Settings")
        .frame(minWidth: 640)
        .frame(maxWidth: .infinity)
        .disabled(appState.isPerformingNetworkOperation)
    }

    // MARK: - Detail

    private var paneDetail: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                switch pane {
                case .general: generalPane
                case .network: networkPane
                case .tun: tunPane
                case .mitm: mitmPane
                case .rules: rulesPane
                }

                Color.clear.frame(height: DS.Space.xs)
            }
            .padding(DS.Space.xl)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.never)
        .background(DS.canvas)
    }

    // MARK: - General pane

    private var generalPane: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            paneHeader("General", subtitle: "Startup, appearance and diagnostics")

            DSCard {
                DSCardHeader("Startup & Appearance", icon: "power", subtitle: "Launch behaviour and theme")

                VStack(alignment: .leading, spacing: DS.Space.md) {
                    settingToggle("Start with macOS", isOn: $autoStart)
                        .onChange(of: autoStart) { _, newValue in
                            Task {
                                try? LaunchService.shared.setLaunchAtLogin(enabled: newValue)
                            }
                        }

                    settingToggle("Silent Start", isOn: $silentStart)

                    settingRow("Theme") {
                        Picker("Theme", selection: $theme) {
                            Text("System").tag("system")
                            Text("Light").tag("light")
                            Text("Dark").tag("dark")
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 150)
                        .onChange(of: theme) { _, newValue in
                            Task { @MainActor in
                                ThemeService.shared.theme = newValue
                            }
                        }
                    }
                }
            }

            DSCard {
                DSCardHeader("Menu Bar", icon: "menubar.rectangle")
                settingToggle("Show latency next to Ares", isOn: $menuBarShowsLatency)
            }

            DSCard {
                DSCardHeader("Logging", icon: "doc.text.magnifyingglass", subtitle: "Core log verbosity")

                VStack(alignment: .leading, spacing: DS.Space.md) {
                    settingRow("Log Level") {
                        Picker("Log Level", selection: $logLevel) {
                            Text("Silent").tag("silent")
                            Text("Error").tag("error")
                            Text("Warning").tag("warning")
                            Text("Info").tag("info")
                            Text("Debug").tag("debug")
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 150)
                        .onChange(of: logLevel) { _, newValue in
                            Task {
                                try? await ClashController.shared.setLogLevel(newValue)
                            }
                        }
                    }
                }
            }

            DSCard {
                DSCardHeader("Software Update", icon: "arrow.down.circle")
                settingToggle("Automatically check for updates", isOn: $appUpdates.automaticallyChecks)
                settingRow("Ares \(appUpdates.currentVersion)") {
                    Button(appUpdates.availableVersion.map { "Update to \($0)…" } ?? "Check for Updates…") {
                        appUpdates.checkForUpdates()
                    }
                    .disabled(!appUpdates.canCheck || !appUpdates.isConfigured)
                }
                if !appUpdates.status.isEmpty { settingNote(appUpdates.status) }
            }

            // Maintenance is isolated and tinted so it never reads as a normal setting.
            DSCard {
                DSCardHeader(
                    "Maintenance",
                    icon: "wrench.and.screwdriver",
                    subtitle: "Destructive actions",
                    tint: .statusBad
                )

                HStack(spacing: DS.Space.sm) {
                    Button("Clear Cache") {
                        clearCache()
                    }
                    .buttonStyle(.bordered)

                    Button("Reset to Defaults") {
                        resetSettings()
                    }
                    .buttonStyle(.bordered)
                    .tint(.statusBad)

                    Spacer(minLength: 0)
                }

                settingNote("Clearing the cache removes cached rule and subscription data. Resetting restores default ports, rules and appearance, then restarts the core.")
            }
        }
    }

    // MARK: - Network pane

    private var networkPane: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            paneHeader("Network", subtitle: "Local proxy ports, DNS and fingerprinting") {
                Button("Restart Clash Core") {
                    Task {
                        await clashViewModel.restart()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            DSCard {
                DSCardHeader("Local Ports", icon: "network", subtitle: "Listeners exposed on this machine")

                VStack(alignment: .leading, spacing: DS.Space.md) {
                    settingRow("HTTP Port") {
                        portField($httpPort)
                    }
                    settingRow("SOCKS Port") {
                        portField($socksPort)
                    }
                    settingRow("Mixed Port") {
                        portField($mixedPort)
                    }
                }

                settingNote("Port changes require a core restart to take effect.")
            }

            DSCard {
                DSCardHeader("Traffic", icon: "globe", subtitle: "How the core accepts connections")

                VStack(alignment: .leading, spacing: DS.Space.md) {
                    settingToggle("Allow LAN", isOn: $allowLan)
                    settingToggle("IPv6 Support", isOn: $ipv6)
                }
            }

            DSCard {
                DSCardHeader("DNS", icon: "server.rack", subtitle: "Resolvers used by the core")

                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    settingRow("DNS Servers") {
                        TextField("", text: $dnsServers)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .font(DS.Typography.secondary.monospaced())
                            .frame(width: 300)
                    }

                    settingNote("Comma-separated resolvers, e.g. 223.5.5.5, 119.29.29.29. Requires a core restart.")
                }
            }

            DSCard {
                DSCardHeader("TLS Fingerprint", icon: "hand.raised", subtitle: "Browser impersonation")

                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    settingRow("Profile") {
                        Picker("TLS Fingerprint", selection: $tlsFingerprint) {
                            Text("Disabled (Default)").tag("none")
                            Text("Chrome (Recommended)").tag("chrome")
                            Text("Safari (iOS)").tag("ios")
                            Text("Firefox").tag("firefox")
                            Text("Randomized").tag("random")
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 190)
                        .onChange(of: tlsFingerprint) { _, _ in
                            Task {
                                if clashViewModel.isRunning {
                                    await clashViewModel.restart()
                                }
                            }
                        }
                    }

                    settingNote("Mimic browser fingerprints to bypass DPI and reduce drops for AI models.")
                }
            }
        }
    }

    // MARK: - TUN pane

    private var tunPane: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            paneHeader("TUN", subtitle: "Capture traffic at the network layer")

            DSCard {
                HStack(spacing: DS.Space.md) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable TUN Support")
                            .font(DS.Typography.body.weight(.semibold))
                        Text("All traffic is routed through the core without per-app proxy settings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: DS.Space.md)

                    Toggle("", isOn: Binding(
                        get: { tunEnabled },
                        set: { _ in appState.toggleTUN() }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(clashViewModel.isToggling)
                }
            }

            DSCard {
                DSCardHeader("Interface", icon: "bolt.shield", subtitle: "Stack, MTU and routing")

                VStack(alignment: .leading, spacing: DS.Space.md) {
                    settingRow("Network Stack") {
                        Picker("Network Stack", selection: $tunStack) {
                            Text("Mixed (Recommended)").tag("mixed")
                            Text("System").tag("system")
                            Text("gVisor").tag("gvisor")
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 200)
                    }
                    .disabled(!tunEnabled)

                    settingRow("TUN MTU") {
                        TextField("", value: $tunMTU, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .font(DS.Typography.body.monospaced())
                            .frame(width: 84)
                    }
                    .disabled(!tunEnabled)

                    settingRow("TUN Device") {
                        TextField("Auto", text: $tunDevice)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .font(DS.Typography.secondary.monospaced())
                            .frame(width: 120)
                    }
                    .disabled(!tunEnabled)

                    settingToggle("Auto Route", isOn: $tunAutoRoute, isEnabled: tunEnabled)
                    settingToggle("Auto Detect Interface", isOn: $tunAutoDetectInterface, isEnabled: tunEnabled)
                }

                settingNote("TUN settings are inert until TUN support is enabled.")
            }

            DSCard {
                DSCardHeader("Connection Tuning", icon: "timer", subtitle: "Keep-alive and UDP handling")

                VStack(alignment: .leading, spacing: DS.Space.md) {
                    settingRow("Keep-Alive Interval") {
                        TextField("", value: $keepAliveInterval, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .font(DS.Typography.body.monospaced())
                            .frame(width: 84)
                    }

                    settingRow("UDP Timeout") {
                        TextField("", value: $udpTimeout, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .font(DS.Typography.body.monospaced())
                            .frame(width: 84)
                    }
                }
            }

            DSCard {
                DSCardHeader("Notes", icon: "info.circle", subtitle: "Before you enable TUN")

                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    DSKeyValueRow(label: "Privileges", value: "Administrator required", monospaced: false)
                    DSKeyValueRow(label: "Mixed stack", value: "System TCP + gVisor UDP", monospaced: false)
                    DSKeyValueRow(label: "MTU", value: "1400 recommended", monospaced: false)
                    DSKeyValueRow(label: "Changes", value: "Core restart required", monospaced: false)
                }
            }
        }
    }

    // MARK: - MITM pane

    private var mitmPane: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            paneHeader("MITM", subtitle: "TLS interception for request inspection")

            DSCard {
                DSCardHeader("Certificate Authority", icon: "lock.shield", subtitle: "Root CA used to sign intercepted hosts")

                HStack(spacing: DS.Space.sm) {
                    DSStatusPill(
                        text: certManager.isRootCAInstalled ? "Installed" : "Not installed",
                        status: certManager.isRootCAInstalled ? .good : .critical
                    )

                    Spacer(minLength: DS.Space.sm)

                    Button("Install to System") {
                        Task {
                            try? await certManager.installToKeychain()
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(certManager.isRootCAInstalled)

                    Button("Export") {
                        exportCertificate()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                settingNote("Interception only works once the Ares root certificate is trusted by the system keychain.")
            }

            DSCard {
                DSCardHeader("Interception", icon: "arrow.left.arrow.right", subtitle: "What gets decrypted")

                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    Text("Intercept Ports")
                        .font(DS.Typography.body.weight(.medium))
                    TextField("Ports", text: $mitmPorts)
                        .textFieldStyle(.roundedBorder)
                        .font(DS.Typography.secondary.monospaced())
                    settingNote("Comma-separated ports to intercept, e.g. 80, 443, 8888.")
                }

                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    Text("Host Whitelist")
                        .font(DS.Typography.body.weight(.medium))
                    TextField("Hosts (empty = all)", text: $mitmHosts)
                        .textFieldStyle(.roundedBorder)
                        .font(DS.Typography.secondary.monospaced())
                    settingNote("Comma-separated hosts and IPs to intercept, e.g. 10.10.25.251, api.example.com. Leave empty to intercept everything.")
                }
            }
        }
    }

    // MARK: - Rules pane

    private var rulesPane: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            paneHeader("Rules", subtitle: "Bypass list and custom routing") {
                Button("Apply Proxy Rules") {
                    applyProxyRules()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            DSCard {
                DSCardHeader("Bypass Domains", icon: "arrow.uturn.left", subtitle: "Traffic that skips the proxy")

                codeEditor($bypassRules, height: 100)

                settingNote("Comma-separated domains and IP ranges, e.g. localhost, 127.*, 192.168.*.")
            }

            DSCard {
                DSCardHeader("Custom Routing Rules", icon: "list.bullet.rectangle", subtitle: "Highest priority, applied to the top of `rules:`")

                codeEditor($localRules, height: 120)
                    .onChange(of: localRules) { _, _ in
                        // Debounce: cancel any pending restart, schedule a new one 1.5s after typing stops.
                        localRulesRestartTask?.cancel()
                        localRulesRestartTask = Task {
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            if Task.isCancelled { return }
                            if clashViewModel.isRunning {
                                await clashViewModel.restart()
                            }
                        }
                    }

                settingNote("One rule per line in mihomo syntax, e.g. `DOMAIN-SUFFIX,z.ai,DIRECT`. Survives subscription updates and applies automatically 1.5s after you stop typing.")
            }
        }
    }

    // MARK: - Building blocks

    private func paneHeader<Trailing: View>(
        _ title: String,
        subtitle: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: DS.Space.md) {
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(title)
                    .font(DS.Typography.sectionTitle.weight(.semibold))
                Text(subtitle)
                    .font(DS.Typography.metadata)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: DS.Space.md)

            trailing()
        }
    }

    private func paneHeader(_ title: String, subtitle: String) -> some View {
        paneHeader(title, subtitle: subtitle) { EmptyView() }
    }

    private func settingRow<Control: View>(
        _ title: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        LabeledContent {
            control()
        } label: {
            Text(title)
        }
        .labeledContentStyle(SettingRowStyle())
    }

    private func settingToggle(_ title: String, isOn: Binding<Bool>, isEnabled: Bool = true) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(DS.Typography.body.weight(.medium))
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .disabled(!isEnabled)
    }

    private func settingNote(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func portField(_ text: Binding<String>) -> some View {
        TextField("", text: text)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .font(DS.Typography.body.monospaced())
            .frame(width: 84)
    }

    /// Inset editing surface: fill only, no hand-rolled textBackgroundColor + stroke chrome.
    private func codeEditor(_ text: Binding<String>, height: CGFloat) -> some View {
        TextEditor(text: text)
            .font(DS.Typography.secondary.monospaced())
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            .padding(DS.Space.sm)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
    }

    // MARK: - Actions

    private func exportCertificate() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "ares-root-ca.crt"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                Task {
                    try? await certManager.exportRootCA(to: url)
                }
            }
        }
    }

    private func applyProxyRules() {
        Task {
            // 0. Refresh MITM Backend whitelist (for display filtering and connection bypass)
            await MITMBackend.shared.refreshDisplayWhitelist()

            // 1. Refresh system proxy with new rules if currently enabled
            if appState.systemProxyEnabled {
                _ = await appState.enableSystemProxy()
            }

            // 2. If TUN mode is active, we MUST restart Clash to rebuild config with new MITM domain rules
            if tunEnabled {
                let wasMITMRunning = NetworkMITMService.shared.isRunning

                // Stop MITM first to prevent errors during Clash restart
                if wasMITMRunning {
                    await NetworkMITMService.shared.stop()
                }

                await clashViewModel.restart()

                // Restart MITM only when it was actually running before the rebuild.
                if wasMITMRunning {
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s wait for Core stability
                    await NetworkMITMService.shared.start()
                }
            }

            clashViewModel.addLog("[Settings] ✅ Proxy rules applied")
        }
    }

    private func clearCache() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let cacheDir = appSupport.appendingPathComponent("Ares/cache")
        try? FileManager.default.removeItem(at: cacheDir)
        clashViewModel.addLog("[Settings] Cache cleared", level: .debug)
    }

    private func resetSettings() {
        httpPort = "\(ClashPorts.defaultHttp)"
        socksPort = "\(ClashPorts.defaultSocks)"
        mixedPort = "\(ClashPorts.defaultMixed)"
        allowLan = false
        ipv6 = false
        logLevel = "info"
        autoStart = false
        silentStart = true
        theme = "system"
        menuBarShowsLatency = false
        bypassRules = "localhost,127.*,10.*,172.16.*,172.31.*,192.168.*"
        localRules = ""
        tunStack = "system"
        tunMTU = 1400
        tunDevice = ""
        tunAutoRoute = true
        tunAutoDetectInterface = true
        keepAliveInterval = 15
        udpTimeout = 120
        dnsServers = "223.5.5.5, 119.29.29.29"

        Task {
            await clashViewModel.restart()
        }
    }
}
