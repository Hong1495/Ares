import SwiftUI
import AppKit
import SubscriptionKit

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
    @State private var confirmRecovery = false

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

    @ObservedObject private var profiles = ProfileService.shared
    @State private var inherited: [String: EffectiveConfiguration.Field] = [:]
    @State private var localKeys = Set<String>()
    @State private var savedLocalKeys = Set<String>()
    @State private var sourcesReady = false
    @State private var sourceRevision = ""
    @State private var sourceError: String?
    @State private var showChanges = false
    @State private var showDNS = false
    @State private var showScenes = false
    @State private var showEgress = false
    @State private var showRuntimeAudit = false
    @State private var showSourceDiff = false
    @State private var sourceDiffRows: [ConfigurationDiff.Row] = []
    @State private var sourceDiffError: String?
    @State private var loadingSourceDiff = false
    @State private var auditRows: [ConfigurationAudit.Row] = []
    @State private var auditError: String?
    @State private var auditing = false
    @State private var auditDate: Date?

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
                Menu {
                    Button("Subscription → Saved Configuration") { showSourceDiff = true }
                    Button("Verify Running Configuration") { showRuntimeAudit = true }
                    Button("Scenes…") { showScenes = true }.disabled(hasPendingChanges)
                    Button("Routing & Listeners…") { showEgress = true }.disabled(hasPendingChanges)
                    Button("DNS Configuration & Query…") { showDNS = true }.disabled(hasPendingChanges)
                    Divider()
                    Button("Restore Last Verified Configuration…") { confirmRecovery = true }
                } label: {
                    Image(systemName: "checkmark.magnifyingglass").font(.system(size: 14))
                }
                .menuStyle(.borderlessButton).fixedSize()
                .help("Inspect Configuration").accessibilityLabel("Inspect Configuration")
                if pane != .general {
                    Button("Discard") { discardChanges() }
                        .buttonStyle(.borderless).disabled(!hasPendingChanges)
                    Button { showChanges = true } label: {
                        Image(systemName: "doc.text.magnifyingglass").font(.system(size: 14))
                    }
                    .buttonStyle(.borderless).help("Review Changes")
                    .accessibilityLabel("Review Changes")
                    .disabled(!hasPendingChanges || !sourcesReady || sourceRevision != profiles.activeProfileRevision)
                    Button(applying ? "Applying…" : "Apply Changes") { applyChanges() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(applying || !hasPendingChanges || !sourcesReady || sourceRevision != profiles.activeProfileRevision)
                }
            }
            .padding(DS.Space.md)
            .background(DSSurfaceBackground())
            .padding(.horizontal, DS.Space.lg)
            .padding(.top, DS.Space.pageTop)
            .padding(.bottom, DS.Space.md)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
            if let sourceError {
                HStack {
                    Text(sourceError).font(.caption).foregroundStyle(.secondary)
                    Button("Reload") { discardChanges() }.buttonStyle(.borderless)
                }.padding(.horizontal, DS.Space.lg).padding(.bottom, DS.Space.sm)
            }
            paneDetail
        }
        .navigationTitle("Settings")
        .frame(minWidth: 640)
        .frame(maxWidth: .infinity)
        .disabled(appState.isPerformingNetworkOperation || applying)
        .controlSize(.small)
        .onAppear { if savedNetworkValues.isEmpty { savedNetworkValues = networkValues }; autoStart = LaunchService.shared.isEnabled(); certManager.checkRootCA() }
        .task(id: profiles.activeProfileRevision) { await refreshSources() }
        .sheet(isPresented: $showEgress) { EgressSettingsView() }
        .sheet(isPresented: $showScenes, onDismiss: { discardChanges() }) { ScenariosView() }
        .sheet(isPresented: $showDNS) { DNSSettingsView() }
        .sheet(isPresented: $showChanges) { changesReview }
        .sheet(isPresented: $showRuntimeAudit) { runtimeAudit }
        .sheet(isPresented: $showSourceDiff) { sourceDiffReview }
        .onChange(of: clashViewModel.runtimeState) { _, _ in invalidateAudit() }
        .onChange(of: profiles.activeProfileRevision) { _, _ in invalidateAudit() }
        .alert("Settings could not be applied", isPresented: Binding(get: { settingsError != nil }, set: { if !$0 { settingsError = nil } })) {
            Button("OK") { settingsError = nil }
        } message: { Text(settingsError ?? "") }
        .confirmationDialog("Restore the last verified configuration?", isPresented: $confirmRecovery) {
            Button("Restore Configuration") { Task { _ = await ConfigurationCoordinator.restoreLastSuccessful() } }
        } message: {
            Text("Restarts the core using the last verified configuration for this mode and subscription. The current subscription file and local settings are kept. Apply them again to leave recovery mode.")
        }
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
                            guard appState.beginOperation("Updating Log Level") else { return }
                            updatingLogLevel = true
                            Task {
                                defer { updatingLogLevel = false; appState.finishOperation(error: appState.lastOperationError) }
                                do {
                                    if clashViewModel.isRunning { try await ClashController.shared.setLogLevel(value) }
                                    logLevel = value
                                    if clashViewModel.runtimeState.isAPIReady,
                                       (try? await clashViewModel.captureRecoveryCheckpoint()) != nil {
                                        await clashViewModel.persistActiveCheckpoint()
                                    }
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
                    Button("Routing & Listeners…") { showEgress = true }.disabled(hasPendingChanges)
                }
            }

            DSCard {
                SettingsSectionTitle("DNS", icon: "server.rack")

                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    settingRow("DNS Servers", preference: DefaultsKeys.dnsServers) {
                        TextField("", text: $dnsServers)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .font(DS.Typography.secondary.monospaced())
                            .frame(width: 300)
                    }

                    settingNote("Separate resolvers with commas.")
                    HStack {
                        Button("Configuration & Query…") { showDNS = true }
                            .disabled(hasPendingChanges)
                        Spacer()
                        if hasPendingChanges { Text("Apply or discard pending settings first.").font(DS.Typography.metadata).foregroundStyle(.secondary) }
                    }
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
                    settingRow("Network Stack", preference: DefaultsKeys.tunStack) {
                        Picker("Network Stack", selection: $tunStack) {
                            Text("Mixed (Recommended)").tag("mixed")
                            Text("System").tag("system")
                            Text("gVisor").tag("gvisor")
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 200)
                    }


                    settingRow("MTU (bytes)", preference: DefaultsKeys.tunMTU) {
                        TextField("", value: $tunMTU, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .font(DS.Typography.body.monospaced())
                            .frame(width: 84)
                    }


                    settingRow("TUN Device", preference: DefaultsKeys.tunDevice) {
                        TextField("Auto", text: $tunDevice)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .font(DS.Typography.secondary.monospaced())
                            .frame(width: 120)
                    }


                    settingToggle("Auto Route", isOn: $tunAutoRoute, preference: DefaultsKeys.tunAutoRoute)
                    settingToggle("Auto Detect Interface", isOn: $tunAutoDetectInterface, preference: DefaultsKeys.tunAutoDetectInterface)
                }

                settingNote("Interface settings apply when TUN is enabled. Apply Changes restarts the active core.")
            }

            DSCard {
                SettingsSectionTitle("Connection Tuning", icon: "timer")

                VStack(alignment: .leading, spacing: DS.Space.md) {
                    settingRow("Keep-Alive Interval (s)", preference: DefaultsKeys.keepAliveInterval) {
                        TextField("", value: $keepAliveInterval, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .font(DS.Typography.body.monospaced())
                            .frame(width: 84)
                    }

                    settingRow("UDP Timeout (s)", preference: DefaultsKeys.udpTimeout) {
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
        _ title: String, preference: String? = nil,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13))
                if let key = preference {
                    SettingsSourceControl(source: localKeys.contains(key) ? "Local override" : inherited[key]?.source ?? "Loading…",
                        isLocal: localKeys.contains(key), pending: localKeys.contains(key) != savedLocalKeys.contains(key),
                        action: { toggleOwnership(key) })
                        .disabled(!sourcesReady || sourceRevision != profiles.activeProfileRevision)
                }
            }
            Spacer(minLength: 16)
            if let key = preference, !localKeys.contains(key) {
                Text(inherited[key]?.value ?? "—")
                    .font(DS.Typography.secondary.monospaced())
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
                    .frame(maxWidth: 300, alignment: .trailing)
            } else { control().controlSize(.small) }
        }
        .frame(minHeight: 28).frame(maxWidth: .infinity)
    }

    private func settingToggle(_ title: String, isOn: Binding<Bool>, isEnabled: Bool = true,
                               preference: String? = nil) -> some View {
        settingRow(title, preference: preference) {
            Toggle(title, isOn: isOn).labelsHidden().toggleStyle(.switch)
                .controlSize(.small).disabled(!isEnabled)
        }
    }

    private func toggleOwnership(_ key: String) {
        if localKeys.contains(key) { localKeys.remove(key) }
        else {
            // Seed editors from representable inherited values; do not flatten advanced YAML.
            if !savedLocalKeys.contains(key), let field = inherited[key] {
                switch key {
                case DefaultsKeys.dnsServers: if field.value != "Core default" { dnsServers = field.value }
                case DefaultsKeys.tunStack: if let value = field.scalar, ["mixed", "system", "gvisor"].contains(value) { tunStack = value }
                case DefaultsKeys.tunMTU: if let value = field.scalar.flatMap(Int.init) { tunMTU = value }
                case DefaultsKeys.tunDevice: tunDevice = field.scalar ?? ""
                case DefaultsKeys.tunAutoRoute: tunAutoRoute = field.scalar == "true"
                case DefaultsKeys.tunAutoDetectInterface: tunAutoDetectInterface = field.scalar == "true"
                case DefaultsKeys.keepAliveInterval: if let value = field.scalar.flatMap(Int.init) { keepAliveInterval = value }
                case DefaultsKeys.udpTimeout: if let value = field.scalar.flatMap(Int.init) { udpTimeout = value }
                default: break
                }
            }
            localKeys.insert(key)
        }
    }

    private func refreshSources(force: Bool = false) async {
        let revision = profiles.activeProfileRevision
        if !force && sourcesReady && hasPendingChanges && sourceRevision != revision {
            sourceError = "The subscription changed. Discard edits and reload before applying."
            return
        }
        sourcesReady = false
        do {
            if profiles.activeProfile != nil && profiles.activeProfile?.path == nil {
                throw EffectiveConfiguration.BuildError.invalidDocument
            }
            let fields = try await ConfigService.shared.inheritedSettings(profilePath: profiles.activeProfile?.path)
            guard !Task.isCancelled, revision == profiles.activeProfileRevision else { return }
            inherited = fields
            localKeys = Set(ProfileConfigMerge.inheritablePaths.keys.filter { UserDefaults.standard.object(forKey: $0) != nil })
            savedLocalKeys = localKeys
            sourceRevision = revision
            sourceError = nil
            sourcesReady = true
        } catch {
            sourceError = "Could not read subscription settings. Reload before applying changes."
        }
    }

    private func discardChanges() {
        loadNetworkSettings()
        localKeys = savedLocalKeys
        Task { await refreshSources(force: true) }
    }

    private func displayedValue(_ key: String, values: [String: Any], locals: Set<String>) -> String {
        if ProfileConfigMerge.inheritablePaths[key] != nil && !locals.contains(key) {
            return inherited[key]?.value ?? "—"
        }
        if let value = values[key] as? Bool { return value ? "true" : "false" }
        let text = values[key].map { String(describing: $0) } ?? ""
        return text.isEmpty ? "Auto / empty" : text
    }

    private var changedKeys: [String] {
        networkValues.keys.filter { key in
            if localKeys.contains(key) != savedLocalKeys.contains(key) { return true }
            if ProfileConfigMerge.inheritablePaths[key] != nil && !localKeys.contains(key) { return false }
            return !NSDictionary(dictionary: [key: networkValues[key]!]).isEqual(to: [key: savedNetworkValues[key] ?? ""])
        }.sorted()
    }

    private var changesReview: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            Text("Pending Changes").font(.headline)
            Text("Proposed configuration, not live core values. Validation runs before the core restarts.")
                .font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.md) {
                    ForEach(changedKeys, id: \.self) { key in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(ProfileConfigMerge.preferencePaths[key]?.joined(separator: ".") ?? key)
                                .font(DS.Typography.body)
                            Text(displayedValue(key, values: savedNetworkValues, locals: savedLocalKeys) + " → " +
                                 displayedValue(key, values: networkValues, locals: localKeys))
                                .font(DS.Typography.secondary.monospaced()).textSelection(.enabled)
                            if ProfileConfigMerge.inheritablePaths[key] != nil {
                                Text(localKeys.contains(key) ? "Local override" : inherited[key]?.source ?? "Inherited")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            HStack { Spacer(); Button("Done") { showChanges = false }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 520, height: 380)
    }

    private var sourceDiffReview: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack {
                Text("Subscription → Saved Configuration").font(.headline)
                Spacer()
                Button(loadingSourceDiff ? "Loading…" : "Reload") { Task { await loadSourceDiff() } }
                    .disabled(loadingSourceDiff)
            }
            Text("Complete structural changes, including list order. Sensitive values and custom names are hidden. Saved configuration is not proof of the running state.")
                .font(.caption).foregroundStyle(.secondary)
            if let sourceDiffError { Text(sourceDiffError).font(.callout).foregroundStyle(.secondary) }
            Text("\(sourceDiffRows.count) changed fields").font(.caption).foregroundStyle(.secondary)
            Table(sourceDiffRows) {
                TableColumn("Field") { Text($0.path).font(.system(size: 12, design: .monospaced)).help($0.path) }
                    .width(min: 200, ideal: 300)
                TableColumn("Subscription") { Text($0.before) }
                TableColumn("Saved") { Text($0.after) }
                TableColumn("Change") { Text($0.change) }.width(75)
            }
            HStack { Spacer(); Button("Done") { showSourceDiff = false }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 780, height: 480)
        .task { await loadSourceDiff() }
    }

    private func loadSourceDiff() async {
        guard !loadingSourceDiff else { return }
        loadingSourceDiff = true
        sourceDiffRows = []; sourceDiffError = nil
        defer { loadingSourceDiff = false }
        let revision = profiles.activeProfileRevision
        let mode = tunEnabled
        do {
            guard !appState.isPerformingNetworkOperation,
                  profiles.activeProfile == nil || profiles.activeProfile?.path != nil else { throw CancellationError() }
            let rows = try await ConfigService.shared.sourceDifferences(profilePath: profiles.activeProfile?.path, tunEnabled: mode)
            guard !Task.isCancelled, revision == profiles.activeProfileRevision, mode == tunEnabled,
                  !appState.isPerformingNetworkOperation else { throw CancellationError() }
            sourceDiffRows = rows
        } catch {
            sourceDiffError = "Could not compare stable saved files. A validated configuration must exist for this mode."
        }
    }

    private func invalidateAudit() {
        sourceDiffRows = []
        if showSourceDiff { sourceDiffError = "Runtime or subscription changed. Reload the comparison." }
        auditRows = []
        auditDate = nil
        if showRuntimeAudit { auditError = "Runtime or subscription changed. Check again." }
    }

    private var runtimeAudit: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack {
                Text("Running Configuration").font(.headline)
                Spacer()
                Button(auditing ? "Checking…" : "Check Again") { Task { await checkRuntime() } }
                    .disabled(auditing || appState.isPerformingNetworkOperation)
            }
            Text("Compares the saved configuration file with the core’s current response. Unsaved edits are excluded. Live changes can differ from the file. Not exposed means the API cannot verify that field.")
                .font(.caption).foregroundStyle(.secondary)
            if let auditError { Text(auditError).font(.callout).foregroundStyle(.secondary) }
            if let auditDate {
                HStack {
                    Text("Checked \(auditDate.formatted(date: .omitted, time: .standard))")
                    Spacer()
                    Text("\(auditRows.filter { $0.status == .different }.count) differences")
                }.font(.caption).foregroundStyle(.secondary)
            }
            SettingsRuntimeTable(rows: auditRows.map {
                SettingsRuntimeRow(id: $0.id, saved: $0.configured, running: $0.running,
                                   result: $0.status.rawValue, differs: $0.status == .different)
            })
            HStack { Spacer(); Button("Done") { showRuntimeAudit = false }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 720, height: 480)
        .task { await checkRuntime() }
    }

    private func checkRuntime() async {
        guard !auditing else { return }
        auditRows = []; auditDate = nil; auditError = nil
        guard clashViewModel.runtimeState.isAPIReady, !appState.isPerformingNetworkOperation else {
            auditError = "The core is stopped or changing configuration. No verification was performed."
            return
        }
        auditing = true
        defer { auditing = false }
        let controller = ClashController.shared
        let generation = controller.runtimeGeneration
        let mode = tunEnabled
        let revision = profiles.activeProfileRevision
        do {
            let saved = try await ConfigService.shared.savedConfiguration(tunEnabled: mode)
            let response = try await controller.readRuntimeConfiguration()
            let unchanged = try await ConfigService.shared.savedConfiguration(tunEnabled: mode)
            guard !Task.isCancelled, saved == unchanged, mode == tunEnabled,
                  generation == controller.runtimeGeneration, revision == profiles.activeProfileRevision,
                  clashViewModel.runtimeState.isAPIReady, !appState.isPerformingNetworkOperation else {
                throw CancellationError()
            }
            auditRows = try ConfigurationAudit.compare(configuration: saved, response: response)
            auditDate = Date()
        } catch {
            auditError = "Could not verify a stable runtime. Check again when the core is running."
        }
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
            .scrollIndicators(.never)
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
        needsProxyRetry || !changedKeys.isEmpty
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
        guard sourcesReady, sourceRevision == profiles.activeProfileRevision else {
            settingsError = "Reload subscription settings before applying changes."
            return
        }
        if let error = SettingsValidation.error(http: httpPort, socks: socksPort, mixed: mixedPort,
                                                mtu: localKeys.contains(DefaultsKeys.tunMTU) ? tunMTU : 1400,
                                                keepAlive: localKeys.contains(DefaultsKeys.keepAliveInterval) ? keepAliveInterval : 15,
                                                udpTimeout: localKeys.contains(DefaultsKeys.udpTimeout) ? udpTimeout : 120,
                                                mitmPorts: mitmPorts,
                                                dns: localKeys.contains(DefaultsKeys.dnsServers) ? dnsServers : "223.5.5.5",
                                                device: localKeys.contains(DefaultsKeys.tunDevice) ? tunDevice : "") {
            settingsError = error
            return
        }
        guard appState.beginOperation("Applying Settings") else { return }
        applying = true
        clashViewModel.isToggling = true
        let previous = savedNetworkValues
        let proposed = networkValues
        let operationMode = tunEnabled
        let operationRevision = profiles.activeProfileRevision
        let wasRunning = clashViewModel.isRunning
        Task {
            defer {
                applying = false
                clashViewModel.isToggling = false
                appState.finishOperation(error: appState.lastOperationError)
            }
            let defaults = UserDefaults.standard
            let removals = Set(ProfileConfigMerge.inheritablePaths.keys).subtracting(localKeys)
            let change = NetworkPreferenceChange(proposed: proposed, displayed: previous, defaults: defaults,
                removals: removals, forced: localKeys.subtracting(savedLocalKeys))
            if wasRunning {
                let checkpoint: RuntimeCheckpoint
                do { checkpoint = try await clashViewModel.captureRecoveryCheckpoint() }
                catch { settingsError = "No verified configuration is available for recovery. Changes were not applied."; return }
                let outcome = await ConfigurationCoordinator.replace(previous: checkpoint, targetMode: operationMode,
                    restoreProxy: appState.systemProxyEnabled,
                    preparePreferences: { change.apply(to: defaults) },
                    restorePreferences: { change.restore(in: defaults) })
                guard outcome == .committed else {
                    switch outcome {
                    case .preparationFailed: settingsError = "Configuration preparation failed. Previous settings were restored."
                    case .unchanged: settingsError = "Core shutdown could not be confirmed. Previous settings were restored."
                    case .restored: settingsError = "The new configuration failed. The previous core and proxy configuration were recovered."
                    default: settingsError = "Configuration recovery could not be verified. Check the runtime before retrying."
                    }
                    return
                }
            } else {
                change.apply(to: defaults)
                do {
                    try await ConfigService.shared.buildConfig(tunEnabled: operationMode)
                    guard operationRevision == profiles.activeProfileRevision, operationMode == tunEnabled else { throw CancellationError() }
                } catch {
                    change.restore(in: defaults)
                    settingsError = "Configuration preparation failed. Settings were restored; the core remains stopped."
                    return
                }
            }
            needsProxyRetry = false
            savedNetworkValues = proposed
            savedLocalKeys = localKeys
            loadNetworkSettings()
            await MITMBackend.shared.refreshDisplayWhitelist()
            if !wasRunning, NetworkMITMService.shared.isRunning {
                guard await NetworkMITMService.shared.updateUpstream(tunEnabled: tunEnabled) else {
                    settingsError = "Could not update the MITM upstream port."; return
                }
            }
            if !wasRunning, appState.systemProxyEnabled, !(await appState.enableSystemProxy()) {
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
        localKeys = Set(ProfileConfigMerge.inheritablePaths.keys)
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
