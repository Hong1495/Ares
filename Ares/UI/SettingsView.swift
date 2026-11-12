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

// MARK: - View

struct SettingsView: View {
    @ObservedObject private var appUpdates = AppUpdateService.shared
    @EnvironmentObject var clashViewModel: ClashViewModel
    @EnvironmentObject var appState: AppState
    @AppStorage(DefaultsKeys.autoStart) private var autoStart = false
    @AppStorage(DefaultsKeys.silentStart) private var silentStart = true
    @AppStorage(DefaultsKeys.theme) private var theme = "system"
    @AppStorage(DefaultsKeys.menuBarShowsLatency) private var menuBarShowsLatency = false

    @AppStorage(DefaultsKeys.ipReputationEnabled) private var ipReputationEnabled = false

    @State private var settingsError: String?
    @State private var applying = false
    @State private var needsProxyRetry = false
    @State private var updatingLogLevel = false
    @State private var confirmReset = false

    // Network edits remain local until Apply Changes validates them.
    @State private var socksPort = UserDefaults.standard.string(forKey: DefaultsKeys.socksPort) ?? "\(ClashPorts.defaultSocks)"
    @State private var httpPort = UserDefaults.standard.string(forKey: DefaultsKeys.httpPort) ?? "\(ClashPorts.defaultHttp)"
    @State private var mixedPort = UserDefaults.standard.string(forKey: DefaultsKeys.mixedPort) ?? "\(ClashPorts.defaultMixed)"
    @State private var allowLan = UserDefaults.standard.object(forKey: DefaultsKeys.allowLan) as? Bool ?? false
    @State private var ipv6 = UserDefaults.standard.object(forKey: DefaultsKeys.ipv6) as? Bool ?? false
    @AppStorage(DefaultsKeys.logLevel) private var logLevel = "info"
    @State private var dnsServers = UserDefaults.standard.string(forKey: DefaultsKeys.dnsServers) ?? "223.5.5.5, 119.29.29.29"

    // TUN Mode
    @State private var tunStack = UserDefaults.standard.string(forKey: DefaultsKeys.tunStack) ?? "system"
    @State private var tunMTU = UserDefaults.standard.object(forKey: DefaultsKeys.tunMTU) as? Int ?? 1400
    @State private var tunDevice = UserDefaults.standard.string(forKey: DefaultsKeys.tunDevice) ?? ""
    @State private var tunAutoRoute = UserDefaults.standard.object(forKey: DefaultsKeys.tunAutoRoute) as? Bool ?? true
    @State private var tunAutoDetectInterface = UserDefaults.standard.object(forKey: DefaultsKeys.tunAutoDetectInterface) as? Bool ?? true
    @State private var keepAliveInterval = UserDefaults.standard.object(forKey: DefaultsKeys.keepAliveInterval) as? Int ?? 15
    @State private var udpTimeout = UserDefaults.standard.object(forKey: DefaultsKeys.udpTimeout) as? Int ?? 120

    // System Proxy Bypass
    @State private var bypassRules = UserDefaults.standard.string(forKey: DefaultsKeys.bypassRules) ?? "localhost,127.*,10.*,172.16.0.0/12,192.168.*"

    // Custom Routing Rules (highest priority, injected at top of `rules:` — survives subscription updates)
    @State private var localRules = UserDefaults.standard.string(forKey: DefaultsKeys.localRules) ?? ""

    // MITM Settings
    @ObservedObject private var certManager = CertificateManager.shared
    @State private var mitmPorts = UserDefaults.standard.string(forKey: DefaultsKeys.mitmPorts) ?? "80, 443, 8080, 8443"
    @State private var mitmHosts = UserDefaults.standard.string(forKey: DefaultsKeys.mitmHosts) ?? ""
    @State private var tlsFingerprint = UserDefaults.standard.string(forKey: DefaultsKeys.tlsFingerprint) ?? "none"

    @State private var pane: SettingsPane = .general

    private var tunEnabled: Bool { appState.tunEnabled }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Space.md) {
                SettingsTabs(titles: SettingsPane.allCases.map(\.title), selection: Binding(
                    get: { SettingsPane.allCases.firstIndex(of: pane) ?? 0 },
                    set: { pane = SettingsPane.allCases[$0] }
                ))
                Spacer(minLength: DS.Space.sm)
                if pane != .general {
                    Button("Discard") { loadNetworkSettings() }
                        .buttonStyle(.borderless).disabled(!hasPendingChanges)
                    Button(applying ? "Applying…" : "Apply Changes") { applyChanges() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(applying || !hasPendingChanges)
                }
            }
            .padding(DS.Space.md)
            .background(DSSurfaceBackground())
            .padding(.horizontal, DS.Space.lg)
            .padding(.top, DS.Space.pageTop)
            .padding(.bottom, DS.Space.md)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
            paneDetail
        }
        .navigationTitle("Settings")
        .frame(minWidth: 640)
        .frame(maxWidth: .infinity)
        .disabled(appState.isPerformingNetworkOperation || applying)
        .controlSize(.small)
        .onAppear { if savedNetworkValues.isEmpty { savedNetworkValues = networkValues }; autoStart = LaunchService.shared.isEnabled(); certManager.checkRootCA() }
        .alert("Settings could not be applied", isPresented: Binding(get: { settingsError != nil }, set: { if !$0 { settingsError = nil } })) {
            Button("OK") { settingsError = nil }
        } message: { Text(settingsError ?? "") }
        .confirmationDialog("Reset settings to defaults?", isPresented: $confirmReset) {
            Button("Reset Settings", role: .destructive) { resetSettings() }
        } message: {
            Text("This resets preferences and restarts the running core. Subscriptions, trusted certificates and the current TUN state are kept.")
        }
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
            .padding(.horizontal, DS.Space.lg)
            .padding(.bottom, DS.Space.lg)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollIndicators(.never)
        .background(DS.canvas)
    }

    // MARK: - General pane

    private var generalPane: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {

            DSCard {
                SettingsSectionTitle("Startup & Appearance", icon: "power")

                VStack(alignment: .leading, spacing: DS.Space.md) {
                    settingToggle("Start with macOS", isOn: Binding(get: { autoStart }, set: { value in
                        do {
                            try LaunchService.shared.setLaunchAtLogin(enabled: value)
                            autoStart = LaunchService.shared.isEnabled()
                            if value && !autoStart { settingsError = "Allow Ares in System Settings → General → Login Items." }
                        } catch { settingsError = "Could not change the login item. Check System Settings → General → Login Items." }
                    }))

                    settingToggle("Open in menu bar only", isOn: $silentStart)

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
                SettingsSectionTitle("Menu Bar", icon: "menubar.rectangle")
                settingToggle("Show latency next to Ares", isOn: $menuBarShowsLatency)
            }

            DSCard {
                SettingsSectionTitle("Exit IP Reputation", icon: "checkmark.shield")
                settingToggle("Automatically check IP risk", isOn: $ipReputationEnabled)
                    .onChange(of: ipReputationEnabled) { _, enabled in
                        if !enabled { IPReputationService.shared.clear() }
                    }
                settingNote("Checks the exit IP shown on Dashboard using proxycheck.io. Shares that IP with the provider. Checks when Dashboard is open; refreshes after an IP change or every 6 hours. Risk is 0–100, lower is better; VPN and hosting status can raise it.")
                Link("About the risk score", destination: URL(string: "https://proxycheck.io/api/")!)
                    .font(.system(size: 12))
            }

            DSCard {
                SettingsSectionTitle("Logging", icon: "doc.text.magnifyingglass")

                VStack(alignment: .leading, spacing: DS.Space.md) {
                    settingRow("Log Level") {
                        Picker("Log Level", selection: Binding(get: { logLevel }, set: { value in
                            updatingLogLevel = true
                            Task {
                                defer { updatingLogLevel = false }
                                do {
                                    if clashViewModel.isRunning { try await ClashController.shared.setLogLevel(value) }
                                    logLevel = value
                                } catch { settingsError = "Could not update the log level. Previous setting was kept." }
                            }
                        })) {
                            Text("Silent").tag("silent")
                            Text("Error").tag("error")
                            Text("Warning").tag("warning")
                            Text("Info").tag("info")
                            Text("Debug").tag("debug")
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 150)
                        .disabled(updatingLogLevel)
                    }
                }
            }

            DSCard {
                SettingsSectionTitle("Software Update", icon: "arrow.down.circle")
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
                SettingsSectionTitle("Maintenance", icon: "wrench.and.screwdriver")

                HStack(spacing: DS.Space.sm) {
                    Button("Clear Cache") {
                        clearCache()
                    }
                    .buttonStyle(.bordered)

                    Button("Reset to Defaults") {
                        confirmReset = true
                    }
                    .buttonStyle(.bordered)
                    .tint(.statusBad)

                    Spacer(minLength: 0)
                }

                settingNote("Clears downloaded response cache. Subscriptions and routing data are kept.")
            }
        }
    }

    // MARK: - Network pane

    private var networkPane: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {

            DSCard {
                SettingsSectionTitle("Local Ports", icon: "network")

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

                settingNote(tunEnabled ? "TUN uses dedicated ports. These ports apply in normal proxy mode." : "Apply Changes restarts the running core.")
            }

            DSCard {
                SettingsSectionTitle("Traffic", icon: "globe")

                VStack(alignment: .leading, spacing: DS.Space.md) {
                    settingToggle("Allow LAN", isOn: $allowLan)
                    settingToggle("IPv6 Support", isOn: $ipv6)
                }
            }

            DSCard {
                SettingsSectionTitle("DNS", icon: "server.rack")

                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    settingRow("DNS Servers") {
                        TextField("", text: $dnsServers)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .font(DS.Typography.secondary.monospaced())
                            .frame(width: 300)
                    }

                    settingNote("Separate resolvers with commas.")
                }
            }

            DSCard {
                SettingsSectionTitle("TLS Fingerprint", icon: "hand.raised")

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

                    }

                    settingNote("Default for supported nodes without their own TLS fingerprint.")
                }
            }
        }
    }

    // MARK: - TUN pane

    private var tunPane: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {

            DSCard {
                HStack(spacing: DS.Space.md) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable TUN Support")
                            .font(DS.Typography.body.weight(.semibold))
                        Text("Route device traffic through a virtual interface.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: DS.Space.md)

                    Toggle("", isOn: Binding(
                        get: { tunEnabled },
                        set: { _ in
                            if hasPendingChanges { settingsError = "Apply or discard your changes before switching TUN." }
                            else { appState.toggleTUN() }
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(clashViewModel.isToggling)
                }
            }

            DSCard {
                SettingsSectionTitle("Interface", icon: "bolt.shield")

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


                    settingRow("MTU (bytes)") {
                        TextField("", value: $tunMTU, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .font(DS.Typography.body.monospaced())
                            .frame(width: 84)
                    }


                    settingRow("TUN Device") {
                        TextField("Auto", text: $tunDevice)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .font(DS.Typography.secondary.monospaced())
                            .frame(width: 120)
                    }


                    settingToggle("Auto Route", isOn: $tunAutoRoute, isEnabled: true)
                    settingToggle("Auto Detect Interface", isOn: $tunAutoDetectInterface, isEnabled: true)
                }

                settingNote("Administrator access is required to enable TUN. Apply Changes restarts the active core.")
            }

            DSCard {
                SettingsSectionTitle("Connection Tuning", icon: "timer")

                VStack(alignment: .leading, spacing: DS.Space.md) {
                    settingRow("Keep-Alive Interval (s)") {
                        TextField("", value: $keepAliveInterval, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .font(DS.Typography.body.monospaced())
                            .frame(width: 84)
                    }

                    settingRow("UDP Timeout (s)") {
                        TextField("", value: $udpTimeout, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .font(DS.Typography.body.monospaced())
                            .frame(width: 84)
                    }
                }
            }


        }
    }

    // MARK: - MITM pane

    private var mitmPane: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {

            DSCard {
                SettingsSectionTitle("Certificate Authority", icon: "lock.shield")

                HStack(spacing: DS.Space.sm) {
                    DSStatusPill(
                        text: certManager.isRootCAInstalled ? "Trusted" : "Not trusted",
                        status: certManager.isRootCAInstalled ? .good : .critical
                    )

                    Spacer(minLength: DS.Space.sm)

                    Button("Trust Certificate…") {
                        Task {
                            do { try await certManager.installToKeychain() }
                            catch { settingsError = "Could not install the certificate. Check the authorization and try again." }
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

                settingNote("Interception only works once the Ares root certificate is trusted in your login keychain.")
            }

            DSCard {
                SettingsSectionTitle("Interception", icon: "arrow.left.arrow.right")

                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    Text("Intercept Ports")
                        .font(DS.Typography.body)
                    TextField("Ports", text: $mitmPorts)
                        .textFieldStyle(.roundedBorder)
                        .font(DS.Typography.secondary.monospaced())
                    settingNote("TUN interception ports. Used when the host list is empty.")
                }

                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    Text("Host Whitelist")
                        .font(DS.Typography.body)
                    TextField("Hosts (empty = all)", text: $mitmHosts)
                        .textFieldStyle(.roundedBorder)
                        .font(DS.Typography.secondary.monospaced())
                    settingNote("Filters captured hosts in proxy mode; controls routing in TUN mode. Empty means all hosts.")
                }
            }
        }
    }

    // MARK: - Rules pane

    private var rulesPane: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {

            DSCard {
                SettingsSectionTitle("Bypass Domains", icon: "arrow.uturn.left")

                codeEditor($bypassRules, height: 100)

                settingNote("Comma-separated domains and IP ranges, e.g. localhost, 127.*, 192.168.*.")
            }

            DSCard {
                SettingsSectionTitle("Custom Routing Rules", icon: "list.bullet.rectangle")

                codeEditor($localRules, height: 120)


                settingNote("One rule per line, e.g. DOMAIN-SUFFIX,example.com,DIRECT. Takes priority over subscription rules. Use Apply Changes to activate.")
            }
        }
    }

    // MARK: - Building blocks

    private func settingRow<Control: View>(
        _ title: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        LabeledContent {
            control()
        } label: {
            Text(title)
        }
        .labeledContentStyle(SettingsRowStyle())
    }

    private func settingToggle(_ title: String, isOn: Binding<Bool>, isEnabled: Bool = true) -> some View {
        LabeledContent(title) {
            Toggle(title, isOn: isOn).labelsHidden().toggleStyle(.switch)
                .controlSize(.small).disabled(!isEnabled)
        }.labeledContentStyle(SettingsRowStyle())
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
                    do { try await certManager.exportRootCA(to: url) }
                    catch { settingsError = "Could not export the certificate to this location." }
                }
            }
        }
    }

    private var networkValues: [String: Any] {
        [
            DefaultsKeys.socksPort: socksPort.trimmingCharacters(in: .whitespaces),
            DefaultsKeys.httpPort: httpPort.trimmingCharacters(in: .whitespaces),
            DefaultsKeys.mixedPort: mixedPort.trimmingCharacters(in: .whitespaces),
            DefaultsKeys.allowLan: allowLan,
            DefaultsKeys.ipv6: ipv6,
            DefaultsKeys.dnsServers: dnsServers,
            DefaultsKeys.tunStack: tunStack,
            DefaultsKeys.tunMTU: tunMTU,
            DefaultsKeys.tunDevice: tunDevice,
            DefaultsKeys.tunAutoRoute: tunAutoRoute,
            DefaultsKeys.tunAutoDetectInterface: tunAutoDetectInterface,
            DefaultsKeys.keepAliveInterval: keepAliveInterval,
            DefaultsKeys.udpTimeout: udpTimeout,
            DefaultsKeys.bypassRules: bypassRules,
            DefaultsKeys.localRules: localRules,
            DefaultsKeys.mitmPorts: mitmPorts,
            DefaultsKeys.mitmHosts: mitmHosts,
            DefaultsKeys.tlsFingerprint: tlsFingerprint
        ]
    }

    private var hasPendingChanges: Bool {
        needsProxyRetry || !NSDictionary(dictionary: networkValues).isEqual(to: savedNetworkValues)
    }

    @State private var savedNetworkValues: [String: Any] = [:]

    private func loadNetworkSettings() {
        if let value = savedNetworkValues[DefaultsKeys.socksPort] as? String { socksPort = value }
        if let value = savedNetworkValues[DefaultsKeys.httpPort] as? String { httpPort = value }
        if let value = savedNetworkValues[DefaultsKeys.mixedPort] as? String { mixedPort = value }
        if let value = savedNetworkValues[DefaultsKeys.allowLan] as? Bool { allowLan = value }
        if let value = savedNetworkValues[DefaultsKeys.ipv6] as? Bool { ipv6 = value }
        if let value = savedNetworkValues[DefaultsKeys.dnsServers] as? String { dnsServers = value }
        if let value = savedNetworkValues[DefaultsKeys.tunStack] as? String { tunStack = value }
        if let value = savedNetworkValues[DefaultsKeys.tunMTU] as? Int { tunMTU = value }
        if let value = savedNetworkValues[DefaultsKeys.tunDevice] as? String { tunDevice = value }
        if let value = savedNetworkValues[DefaultsKeys.tunAutoRoute] as? Bool { tunAutoRoute = value }
        if let value = savedNetworkValues[DefaultsKeys.tunAutoDetectInterface] as? Bool { tunAutoDetectInterface = value }
        if let value = savedNetworkValues[DefaultsKeys.keepAliveInterval] as? Int { keepAliveInterval = value }
        if let value = savedNetworkValues[DefaultsKeys.udpTimeout] as? Int { udpTimeout = value }
        if let value = savedNetworkValues[DefaultsKeys.bypassRules] as? String { bypassRules = value }
        if let value = savedNetworkValues[DefaultsKeys.localRules] as? String { localRules = value }
        if let value = savedNetworkValues[DefaultsKeys.mitmPorts] as? String { mitmPorts = value }
        if let value = savedNetworkValues[DefaultsKeys.mitmHosts] as? String { mitmHosts = value }
        if let value = savedNetworkValues[DefaultsKeys.tlsFingerprint] as? String { tlsFingerprint = value }
    }

    private func applyChanges() {
        if let error = SettingsValidation.error(http: httpPort, socks: socksPort, mixed: mixedPort,
                                                mtu: tunMTU, keepAlive: keepAliveInterval, udpTimeout: udpTimeout,
                                                mitmPorts: mitmPorts, dns: dnsServers, device: tunDevice) {
            settingsError = error
            return
        }
        guard appState.beginOperation("Applying Settings") else { return }
        applying = true
        clashViewModel.isToggling = true
        let previous = savedNetworkValues
        let proposed = networkValues
        Task {
            defer {
                applying = false
                clashViewModel.isToggling = false
                appState.finishOperation()
            }
            let defaults = UserDefaults.standard
            proposed.forEach { defaults.set($0.value, forKey: $0.key) }
            do {
                // Validate before touching the running core or its system proxy routes.
                try await ConfigService.shared.buildConfig(tunEnabled: tunEnabled)
            } catch {
                previous.forEach { defaults.set($0.value, forKey: $0.key) }
                settingsError = "Configuration validation failed. The running core was kept unchanged. Review Logs for details."
                return
            }
            if clashViewModel.isRunning {
                guard await clashViewModel.stopCore(intendedRestart: true) else {
                    previous.forEach { defaults.set($0.value, forKey: $0.key) }
                    try? await ConfigService.shared.buildConfig(tunEnabled: tunEnabled)
                    settingsError = "Could not stop the core. Previous settings were restored."
                    return
                }
                await clashViewModel.startCore(isRestart: true)
                guard clashViewModel.runtimeState.isAPIReady else {
                    guard await clashViewModel.stopCore(intendedRestart: true) else {
                        settingsError = "The failed core could not be stopped. Review Logs before retrying."
                        return
                    }
                    previous.forEach { defaults.set($0.value, forKey: $0.key) }
                    await clashViewModel.startCore(isRestart: true)
                    settingsError = clashViewModel.runtimeState.isAPIReady
                        ? "The new settings could not start. Previous settings were restored."
                        : "The core could not restart or recover. Review Logs before enabling the proxy."
                    return
                }
            }
            needsProxyRetry = false
            savedNetworkValues = proposed
            loadNetworkSettings()
            await MITMBackend.shared.refreshDisplayWhitelist()
            if NetworkMITMService.shared.isRunning {
                guard await NetworkMITMService.shared.updateUpstream(tunEnabled: tunEnabled) else {
                    settingsError = "Could not update the MITM upstream port."; return
                }
            }
            if appState.systemProxyEnabled, !(await appState.enableSystemProxy()) {
                settingsError = "Core settings were applied, but the system proxy could not be updated. Retry Apply Changes."
                needsProxyRetry = true // Keep retry available.
            }
        }
    }

    private func clearCache() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let cacheDir = appSupport.appendingPathComponent("Ares/cache")
        URLCache.shared.removeAllCachedResponses()
        do {
            if FileManager.default.fileExists(atPath: cacheDir.path) { try FileManager.default.removeItem(at: cacheDir) }
        } catch { settingsError = "Could not clear the temporary cache."; return }
        clashViewModel.addLog("[Settings] Cache cleared", level: .debug)
    }

    private func resetSettings() {
        do {
            if LaunchService.shared.isEnabled() { try LaunchService.shared.setLaunchAtLogin(enabled: false) }
            autoStart = LaunchService.shared.isEnabled()
        } catch { settingsError = "Could not reset the login item."; return }
        httpPort = "\(ClashPorts.defaultHttp)"
        socksPort = "\(ClashPorts.defaultSocks)"
        mixedPort = "\(ClashPorts.defaultMixed)"
        allowLan = false
        ipv6 = false
        logLevel = "info"
        silentStart = true
        theme = "system"
        ThemeService.shared.theme = "system"
        appUpdates.automaticallyChecks = true
        menuBarShowsLatency = false
        bypassRules = "localhost,127.*,10.*,172.16.0.0/12,192.168.*"
        localRules = ""
        tunStack = "system"
        tunMTU = 1400
        tunDevice = ""
        tunAutoRoute = true
        tunAutoDetectInterface = true
        keepAliveInterval = 15
        udpTimeout = 120
        dnsServers = "223.5.5.5, 119.29.29.29"

        mitmPorts = "80, 443, 8080, 8443"
        mitmHosts = ""
        tlsFingerprint = "none"
        applyChanges()
    }
}
