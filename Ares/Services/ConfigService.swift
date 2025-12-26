import Foundation

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
            print("[ConfigService] No active profile, using safe fallback")
            try await buildSafeFallbackConfig()
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
        
        // Parse profile YAML to remove conflicting keys (Performed on Actor background thread)
        var cleanedProfile = removeConflictingKeys(from: profileContent)
        
        // Dynamic Rules: Inject Bypass rules and MITM rules
        // Fetch bypass rules from UserDefaults via MainActor
        let (mitmEnabled, mitmPort, bypassRules, mitmPortsString) = await MainActor.run {
            let mitm = NetworkMITMService.shared
            let defaults = UserDefaults.standard
            return (
                mitm.isRunning,
                Int(mitm.currentPort),
                defaults.string(forKey: "bypassRules") ?? "",
                defaults.string(forKey: "mitmPorts") ?? "80, 443, 8080, 8443"
            )
        }
        
        cleanedProfile = injectDynamicRules(into: cleanedProfile, tunEnabled: tunEnabled, mitmEnabled: mitmEnabled, mitmPort: mitmPort, bypassRules: bypassRules, mitmPortsString: mitmPortsString)
        
        // Build base Clash config with TUN setting (MainActor required for ClashConfig)
        let baseConfig = await MainActor.run {
            var clashConfig = ClashConfig(fromUserDefaults: true)
            clashConfig.enableTun = tunEnabled
            // Note: mitmEnabled/mitmPort no longer used in toYAML()
            return clashConfig.toYAML()
        }
        
        // Merge: base config + cleaned profile
        // Get profile name for comment
        let profileName = await MainActor.run { ProfileService.shared.activeProfile?.name ?? "Unknown" }
        
        let targetPath = getConfigPath(tunEnabled: tunEnabled)
        let targetDir = getConfigDir(tunEnabled: tunEnabled)
        
        // Ensure directory exists
        try? await fileManager.createDirectoryIfNeeded(at: targetDir)
        
        let finalConfig = """
        \(baseConfig)
        
        # Profile Content (\(profileName))
        \(cleanedProfile)
        """
        
        // Write to config.yaml (Async, non-blocking)
        do {
            await MainActor.run {
                ClashViewModel.shared.addLog("[Config] 📝 Writing config content (Preview lines 1-10):")
                let preview = finalConfig.components(separatedBy: "\n").prefix(10).joined(separator: "\n")
                ClashViewModel.shared.addLog(preview)
            }
            try await fileManager.writeText(finalConfig, to: targetPath)
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

    
    /// Remove keys that conflict with our base config
    /// Handles both single-line keys and multi-line blocks (like dns:, tun:, sniffer:)
    nonisolated private func removeConflictingKeys(from yaml: String) -> String {
        // Single-line conflicting keys
        let singleLineKeys = [
            "mixed-port",
            "socks-port",
            "port",
            "mode",
            "log-level",
            "allow-lan",
            "ipv6",
            "external-controller",
            "secret",
            "keep-alive-interval"
        ]
        
        // Multi-line block keys (need to remove entire block including children)
        let blockKeys = [
            "tun",      // Use our own TUN config
            "dns",      // CRITICAL: Avoid duplicate dns: key in TUN mode
            "sniffer"   // Use our own sniffer config in TUN mode
        ]
        
        let lines = yaml.components(separatedBy: .newlines)
        var result: [String] = []
        var skipUntilIndent: Int? = nil  // Track when we're inside a block to skip
        
        for line in lines {
            // Calculate current line's indentation (number of leading spaces)
            let leadingSpaces = line.prefix(while: { $0 == " " || $0 == "\t" }).count
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lower = trimmed.lowercased()
            
            // If we're in skip mode, check if we should exit
            if let blockIndent = skipUntilIndent {
                // Empty lines stay in skip mode
                if trimmed.isEmpty {
                    continue
                }
                // If current line has same or less indentation than block start, exit skip mode
                if leadingSpaces <= blockIndent {
                    skipUntilIndent = nil
                } else {
                    // Still inside the block, skip this line
                    continue
                }
            }
            
            // Check for block keys (multi-line sections)
            var isBlockStart = false
            for key in blockKeys {
                if lower.hasPrefix(key + ":") || lower == key + ":" {
                    isBlockStart = true
                    skipUntilIndent = leadingSpaces
                    break
                }
            }
            
            if isBlockStart {
                continue  // Skip the block header line
            }
            
            // Check for single-line conflicting keys
            var isSingleLineConflict = false
            for key in singleLineKeys {
                if lower.hasPrefix(key + ":") || lower.hasPrefix(key + " :") {
                    isSingleLineConflict = true
                    break
                }
            }
            
            if !isSingleLineConflict {
                result.append(line)
            }
        }
        
        return result.joined(separator: "\n")
    }
    
    /// Inject Dynamic Rules (Bypass & MITM) into existing profile sections
    /// - bypassRules: User-defined bypass domains (DIRECT)
    /// - mitm: MITM interception rules (hijack configured ports)
    /// Inject Dynamic Rules (Bypass & MITM) into existing profile sections
    /// - bypassRules: User-defined bypass domains (DIRECT)
    /// - mitm: MITM interception rules (hijack configured ports)
    nonisolated private func injectDynamicRules(into yaml: String, tunEnabled: Bool, mitmEnabled: Bool, mitmPort: Int, bypassRules: String, mitmPortsString: String) -> String {
        print("[ConfigService] 🛠 Injecting Rules - Bypass: [\(bypassRules)], MITM Ports: [\(mitmPortsString)], TUN: \(tunEnabled), MITM: \(mitmEnabled)")
        
        var result = yaml
        var rulesToInject: [String] = []
        
        // 1. Generate Bypass Rules (Highest Priority)
        let bypassItems = bypassRules.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        
        for item in bypassItems {
            // Smart Parsing for macOS defaults
            if item == "10.*" {
                rulesToInject.append("  - IP-CIDR,10.0.0.0/8,DIRECT")
            } else if item == "127.*" {
                rulesToInject.append("  - IP-CIDR,127.0.0.0/8,DIRECT")
            } else if item == "192.168.*" {
                rulesToInject.append("  - IP-CIDR,192.168.0.0/16,DIRECT")
            } else if item == "172.16.*" {
                rulesToInject.append("  - IP-CIDR,172.16.0.0/12,DIRECT")
            } else if item.contains("/") {
                rulesToInject.append("  - IP-CIDR,\(item),DIRECT")
            } else {
                let domain = item.replacingOccurrences(of: "*.", with: "")
                rulesToInject.append("  - DOMAIN-SUFFIX,\(domain),DIRECT")
            }
        }
        
        // 2. Generate MITM Rules (If Enabled in TUN mode)
        if tunEnabled && mitmEnabled && mitmPort > 0 {
            // Parse user configured MITM ports (Handle both English and Chinese commas)
            let separators = CharacterSet(charactersIn: ",，")
            let targetPorts = mitmPortsString.components(separatedBy: separators).compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            // Default to standard ports if empty
            let validPorts = targetPorts.isEmpty ? [80, 443, 8080, 8443] : targetPorts
            
            // Prevent loop: The MITM port itself MUST be DIRECT
            rulesToInject.append("  - DST-PORT,\(mitmPort),DIRECT")
            
            for port in validPorts {
                // Validation: Ensure valid port range and skip MITM port
                if port > 0 && port < 65536 && port != mitmPort {
                     // Note: Using spaces to ensure indentation matches "rules:" children
                     rulesToInject.append("  - AND,((DST-PORT,\(port)),(NOT,((PROCESS-NAME,Ares)))),MITM-Intercept")
                }
            }
            
            // Inject MITM Proxy Definition
            let mitmProxy = """
              - name: MITM-Intercept
                type: http
                server: 127.0.0.1
                port: \(mitmPort)
            """
            
            if let proxiesRange = result.range(of: "proxies:", options: .caseInsensitive) {
                if let lineEnd = result[proxiesRange.upperBound...].firstIndex(of: "\n") {
                    result.insert(contentsOf: "\n" + mitmProxy, at: lineEnd)
                }
            }
        }
        
        print("[ConfigService] 📋 Generated \(rulesToInject.count) dynamic rules:\n\(rulesToInject.joined(separator: "\n"))")
        
        // 3. Inject Rules Buffer at the top of "rules:"
        if !rulesToInject.isEmpty {
            let dynamicRulesBuffer = rulesToInject.joined(separator: "\n")
            if let rulesRange = result.range(of: "rules:", options: .caseInsensitive) {
                if let lineEnd = result[rulesRange.upperBound...].firstIndex(of: "\n") {
                    result.insert(contentsOf: "\n" + dynamicRulesBuffer, at: lineEnd)
                }
            }
        }
        
        return result
    }
    
    /// Build a safe fallback config when no profile is available
    func buildSafeFallbackConfig() async throws {
        await MainActor.run {
            ClashViewModel.shared.addLog("[Config] ⚠️ No active profile found. Using safe fallback (Empty Config).")
        }
        
        // Use default path (User mode) for fallback if not specified? 
        // Actually fallback usually happens when no profile. We should assume User mode default?
        // Let's assume User mode for fallback safety.
        let targetPath = getConfigPath(tunEnabled: false)
        let targetDir = getConfigDir(tunEnabled: false)
        try? await fileManager.createDirectoryIfNeeded(at: targetDir)
        
        let configYAML = await MainActor.run {
            let clashConfig = ClashConfig(fromUserDefaults: true)
            return clashConfig.toYAML()
        }
        
        let config = """
        \(configYAML)
        
        # Safe Fallback Configuration
        # No active profile selected
        
        proxies: []
        proxy-groups: []
        rules: []
        """
        
        try await fileManager.writeText(config, to: targetPath)
        print("[ConfigService] Safe fallback config created")
    }
}
