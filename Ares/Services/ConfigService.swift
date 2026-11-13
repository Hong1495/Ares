import Foundation
import SubscriptionKit
import Darwin

/// Service for building and managing Clash configuration
/// Handles profile merging and conflict resolution
/// Actor-isolated to prevent blocking MainActor during heavy string processing
actor ConfigService {
    static let shared = ConfigService()
    
    
    // Instead of a single configPath, we generate it dynamically
    private var baseDir: URL
    private let fileManager = AsyncFileManager()
    
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.baseDir = appSupport.appendingPathComponent("Ares")
        // Create base directory immediately
        try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
    }
    
    /// Get config path based on mode
    func getConfigPath(tunEnabled: Bool) -> URL {
        let dirName = tunEnabled ? "clash_root" : "clash_user"
        return baseDir.appendingPathComponent("\(dirName)/config.yaml")
    }
    
    /// Get config directory based on mode
    func getConfigDir(tunEnabled: Bool) -> URL {
        let dirName = tunEnabled ? "clash_root" : "clash_user"
        return baseDir.appendingPathComponent(dirName)
    }
    
    func rememberSuccessfulRuntime(_ checkpoint: RuntimeCheckpoint) throws {
        try RuntimeCheckpointStore.save(checkpoint, directory: baseDir.appendingPathComponent("recovery"))
    }

    func successfulRuntime(tunEnabled: Bool) throws -> RuntimeCheckpoint {
        try RuntimeCheckpointStore.load(directory: baseDir.appendingPathComponent("recovery"), tunEnabled: tunEnabled)
    }

    /// The last validated file on disk, not a claim that the running core loaded it.
    func savedConfiguration(tunEnabled: Bool) async throws -> String {
        try await fileManager.readText(from: getConfigPath(tunEnabled: tunEnabled))
    }

    /// Reuse a previously captured configuration during rollback instead of rebuilding
    /// it from a possibly updated subscription. It still passes strict core validation.
    func restoreConfiguration(_ content: String, tunEnabled: Bool) async throws {
        let directory = getConfigDir(tunEnabled: tunEnabled)
        try await ConfigDirectoryPreparation.shared.prepare(directory)
        try await writeValidatedConfig(content, to: getConfigPath(tunEnabled: tunEnabled), directory: directory)
    }

    /// Complete structural source-to-saved diff; raw documents never leave this service.
    func sourceDifferences(profilePath: URL?, tunEnabled: Bool) async throws -> [ConfigurationDiff.Row] {
        let source: String
        if let profilePath { source = try await fileManager.readText(from: profilePath) }
        else { source = "{}" }
        let saved = try await savedConfiguration(tunEnabled: tunEnabled)
        let rows = try ConfigurationDiff.compare(before: source, after: saved)
        guard saved == (try await savedConfiguration(tunEnabled: tunEnabled)) else { throw CancellationError() }
        if let profilePath {
            guard source == (try await fileManager.readText(from: profilePath)) else { throw CancellationError() }
        }
        return rows
    }

    func ruleSources(configuration: String, profilePath: URL?, localRules: String?) async throws -> RuleSourceDocument.Document {
        let source: String?
        if let profilePath { source = try await fileManager.readText(from: profilePath) }
        else { source = nil }
        let result = try RuleSourceDocument.read(configuration: configuration, subscription: source, localRules: localRules)
        if let profilePath {
            guard source == (try await fileManager.readText(from: profilePath)) else { throw CancellationError() }
        }
        return result
    }

    func policyGroups(profilePath: URL, overrides: String) async throws -> ([PolicyConfiguration.Group], [PolicyConfiguration.Group]) {
        let source = try await fileManager.readText(from: profilePath)
        let inherited = try PolicyConfiguration.read(source)
        let effective = try PolicyConfiguration.read(PolicyConfiguration.apply(source: source, overrides: overrides))
        guard source == (try await fileManager.readText(from: profilePath)) else { throw CancellationError() }
        return (inherited, effective)
    }

    func egressSettings(profilePath: URL, overrides: String) async throws -> (EgressConfiguration.Document, EgressConfiguration.Document) {
        let source = try await fileManager.readText(from: profilePath)
        let inherited = try EgressConfiguration.read(source)
        // Keep outdated drafts editable after a subscription removes or renames a node.
        // The UI overlays explicit fields; applying always runs the complete validation.
        _ = try EgressConfiguration.decode(overrides)
        let effective = inherited
        guard source == (try await fileManager.readText(from: profilePath)) else { throw CancellationError() }
        return (inherited, effective)
    }

    func dnsSettings(profilePath: URL, overrides: String) async throws -> ([String: String], [String: String], [String: String]) {
        let source = try await fileManager.readText(from: profilePath)
        let base = await MainActor.run { ClashConfig().toYAML() }
        let baseline = try EffectiveConfiguration.build(source: source, defaults: base, overrides: [])
        let inherited = try DNSConfiguration.read(baseline)
        let subscription = try DNSConfiguration.read(source)
        let sources = Dictionary(uniqueKeysWithValues: inherited.keys.map { ($0, subscription[$0] == nil ? "App default" : "Subscription") })
        let effective = try DNSConfiguration.read(DNSConfiguration.apply(source: baseline, overrides: overrides))
        guard source == (try await fileManager.readText(from: profilePath)) else { throw CancellationError() }
        return (inherited, effective, sources)
    }

    /// Prospective inherited settings; no core validation, resource downloads or runtime writes.
    func inheritedSettings(profilePath: URL?) async throws -> [String: EffectiveConfiguration.Field] {
        let source: String
        if let profilePath { source = try await fileManager.readText(from: profilePath) }
        else { source = "{}" }
        let base = await MainActor.run {
            var config = ClashConfig()
            // TUN fields describe the configuration to use when TUN is enabled.
            config.enableTun = true
            return config.toYAML()
        }
        return try EffectiveConfiguration.inheritedFields(source: source, defaults: base,
            paths: ProfileConfigMerge.inheritablePaths)
    }

    /// Build config.yaml by merging profile with Clash settings
    func buildConfig(tunEnabled: Bool = false) async throws {
        // Log on MainActor
        await MainActor.run {
            ClashViewModel.shared.addLog("[Config] 📝 Building config (TUN=\(tunEnabled))...")
        }
        
        // Get active profile path (Access MainActor state safely)
        let profilePath: URL? = await MainActor.run {
            ProfileService.shared.activeProfile?.path
        }
        
        guard let path = profilePath else {
            await MainActor.run {
                ClashViewModel.shared.addLog("[Config] No active profile, using safe fallback", level: .debug)
            }
            try await buildSafeFallbackConfig(tunEnabled: tunEnabled)
            return
        }
        
        // Read profile content (Async, non-blocking)
        let profileContent: String
        do {
            profileContent = try await fileManager.readText(from: path)
        } catch {
             await MainActor.run {
                 ClashViewModel.shared.addLog("[Config] ❌ Failed to read profile: \(error)")
             }
             throw error
        }
        
        // Dynamic Rules: Inject Bypass rules and MITM rules
        let (mitmEnabled, mitmPort, bypassRules, localRules, mitmPortsString, mitmHosts, tlsFingerprint) = await MainActor.run {
            let mitm = NetworkMITMService.shared
            let defaults = UserDefaults.standard
            return (
                mitm.isRunning && mitm.routingEnabled,
                Int(mitm.currentPort),
                defaults.string(forKey: DefaultsKeys.bypassRules) ?? "",
                defaults.string(forKey: DefaultsKeys.localRules) ?? "",
                defaults.string(forKey: DefaultsKeys.mitmPorts) ?? "80, 443, 8080, 8443",
                defaults.string(forKey: DefaultsKeys.mitmHosts) ?? "",  // Whitelist domains
                defaults.string(forKey: DefaultsKeys.tlsFingerprint) ?? "none"
            )
        }
        
        let (baseConfig, overrides) = await MainActor.run {
            var config = ClashConfig(fromUserDefaults: true)
            config.enableTun = tunEnabled
            return (config.toYAML(), ProfileConfigMerge.overridePaths(defaults: .standard, tunEnabled: tunEnabled))
        }
        let injections = dynamicRules(tunEnabled: tunEnabled, mitmEnabled: mitmEnabled,
            mitmPort: mitmPort, bypassRules: bypassRules, localRules: localRules,
            mitmPortsString: mitmPortsString, mitmHosts: mitmHosts)
        let policyOverrides = await MainActor.run {
            ProfileService.shared.activeProfileID.map {
                UserDefaults.standard.string(forKey: PolicyGroupService.key($0)) ?? "{}"
            } ?? "{}"
        }
        let policySource = try PolicyConfiguration.apply(source: profileContent, overrides: policyOverrides)
        let dnsOverrides = await MainActor.run {
            ProfileService.shared.activeProfileID.map {
                UserDefaults.standard.string(forKey: DNSSettingsService.key($0)) ?? "{}"
            } ?? "{}"
        }
        // Apply advanced DNS after default inheritance; basic/runtime-owned keys stay separate.
        let mergedConfig = try EffectiveConfiguration.build(source: policySource, defaults: baseConfig,
            overrides: overrides, rules: injections.rules, localProxy: injections.proxy,
            fingerprint: tlsFingerprint)
        let dnsConfig = try DNSConfiguration.apply(source: mergedConfig, overrides: dnsOverrides)
        let egressOverrides = await MainActor.run {
            ProfileService.shared.activeProfileID.map {
                UserDefaults.standard.string(forKey: EgressSettingsService.key($0)) ?? EgressConfiguration.empty
            } ?? EgressConfiguration.empty
        }
        let finalConfig = try EgressConfiguration.apply(source: dnsConfig, overrides: egressOverrides)
        if try EgressConfiguration.decode(egressOverrides) != EgressConfiguration.Overrides() {
            let routing = try EgressConfiguration.read(finalConfig)
            for interface in Set(routing.nodes.map(\.interface) + [routing.interface]) where !interface.isEmpty {
                guard interface.withCString({ if_nametoindex($0) }) != 0 else { throw EgressConfiguration.ValidationError.invalid }
            }
        }

        let targetPath = getConfigPath(tunEnabled: tunEnabled)
        let targetDir = getConfigDir(tunEnabled: tunEnabled)
        
        // Ensure directory exists
        try await ConfigDirectoryPreparation.shared.prepare(targetDir)
        
        // Write to config.yaml (Async, non-blocking)
        do {
            try await writeValidatedConfig(finalConfig, to: targetPath, directory: targetDir)
            await MainActor.run {
                ClashViewModel.shared.addLog("[Config] ✅ Config written to: \(targetPath.lastPathComponent)")
            }
        } catch {
            await MainActor.run {
                ClashViewModel.shared.addLog("[Config] ❌ Failed to write config: \(error)")
            }
            throw error
        }
    }

    
    /// Validate a candidate with the same resource directory before replacing the working file.
    private func writeValidatedConfig(_ content: String, to destination: URL, directory: URL) async throws {
        try await ValidatedConfigurationFile.commit(content, to: destination) { candidate in
            try await CoreManager.shared.validateConfigStrict(configDir: directory, configFile: candidate)
        }
    }

    /// Inject Dynamic Rules (Bypass & MITM) into existing profile sections
    /// - bypassRules: User-defined bypass domains (DIRECT)
    /// - localRules: User-defined raw rules (from Rules interface)
    /// - mitm: MITM interception rules (hijack configured ports/domains)
    /// - mitmHosts: Whitelist domains - only these will be routed to MITM
    nonisolated private func dynamicRules(tunEnabled: Bool, mitmEnabled: Bool, mitmPort: Int, bypassRules: String, localRules: String, mitmPortsString: String, mitmHosts: String) -> (rules: [String], proxy: EffectiveConfiguration.LocalProxy?) {
        var rulesToInject: [String] = []  // No indentation yet
        
        // 1. Generate Local Overrides (Highest Priority)
        // Accept lines with or without a leading "- " (YAML list marker) for user-friendliness.
        let localLines = localRules.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .map { line -> String in
                if line.hasPrefix("- ") {
                    return line
                } else {
                    return "- " + line
                }
            }
        
        rulesToInject.append(contentsOf: localLines)
        
        // 2. Generate Bypass Rules
        let bypassItems = bypassRules.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        
        for item in bypassItems {
            rulesToInject.append("- \(SettingsRouting.predicate(for: item)),DIRECT")
        }
        
        // 3. Generate MITM Rules (If Enabled in TUN mode)
        if tunEnabled && mitmEnabled && mitmPort > 0 {
            // Prevent loop: The MITM port itself MUST be DIRECT
            rulesToInject.append("- DST-PORT,\(mitmPort),DIRECT")
            
            // Parse whitelist domains
            let separators = CharacterSet(charactersIn: ",，\n")
            let whitelistDomains = mitmHosts.components(separatedBy: separators)
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                .filter { !$0.isEmpty }
            
            if !whitelistDomains.isEmpty {
                // Whitelist mode
                for domain in whitelistDomains {
                    rulesToInject.append("- AND,((\(SettingsRouting.predicate(for: domain))),(NOT,((PROCESS-NAME,Ares)))),MITM-Intercept")
                }
            } else {
                // Legacy mode: Intercept ports
                let portSeparators = CharacterSet(charactersIn: ",，")
                let targetPorts = mitmPortsString.components(separatedBy: portSeparators).compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                let validPorts = targetPorts.isEmpty ? [80, 443, 8080, 8443] : targetPorts
                
                for port in validPorts {
                    if port > 0 && port < 65536 && port != mitmPort {
                         rulesToInject.append("- AND,((DST-PORT,\(port)),(NOT,((PROCESS-NAME,Ares)))),MITM-Intercept")
                    }
                }
            }
            
        }
        let rules = rulesToInject.map { String($0.dropFirst(2)) }
        let proxy: EffectiveConfiguration.LocalProxy? = tunEnabled && mitmEnabled && mitmPort > 0
            ? .init(name: "MITM-Intercept", port: mitmPort) : nil
        return (rules, proxy)
    }

    /// Build a safe fallback config when no profile is available
    func buildSafeFallbackConfig(tunEnabled: Bool = false) async throws {
        await MainActor.run {
            ClashViewModel.shared.addLog("[Config] ⚠️ No active profile found. Using safe fallback (Empty Config).")
        }
        
        // Use the requested mode even before the preference has been committed.
        let targetPath = getConfigPath(tunEnabled: tunEnabled)
        let targetDir = getConfigDir(tunEnabled: tunEnabled)
        try await ConfigDirectoryPreparation.shared.prepare(targetDir)
        
        let configYAML = await MainActor.run {
            var clashConfig = ClashConfig(fromUserDefaults: true)
            clashConfig.enableTun = tunEnabled
            return clashConfig.toYAML()
        }
        
        let localSettings = await MainActor.run {
            let defaults = UserDefaults.standard
            return (defaults.string(forKey: DefaultsKeys.bypassRules) ?? "",
                    defaults.string(forKey: DefaultsKeys.localRules) ?? "")
        }
        let injections = dynamicRules(tunEnabled: tunEnabled, mitmEnabled: false, mitmPort: 0,
            bypassRules: localSettings.0, localRules: localSettings.1, mitmPortsString: "", mitmHosts: "")
        let config = try EffectiveConfiguration.build(
            source: "proxies: []\nproxy-groups: []\nrules: [\"MATCH,DIRECT\"]",
            defaults: configYAML, overrides: [], rules: injections.rules)

        try await writeValidatedConfig(config, to: targetPath, directory: targetDir)
        await MainActor.run {
            ClashViewModel.shared.addLog("[Config] Safe fallback config created", level: .debug)
        }
    }

    
}
