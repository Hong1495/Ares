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
        let (mitmEnabled, mitmPort, bypassRules, localRules, mitmPortsString, mitmHosts, tlsFingerprint) = await MainActor.run {
            let mitm = NetworkMITMService.shared
            let defaults = UserDefaults.standard
            return (
                mitm.isRunning,
                Int(mitm.currentPort),
                defaults.string(forKey: "bypassRules") ?? "",
                defaults.string(forKey: "localRules") ?? "",
                defaults.string(forKey: "mitmPorts") ?? "80, 443, 8080, 8443",
                defaults.string(forKey: "mitmHosts") ?? "",  // Whitelist domains
                defaults.string(forKey: "tlsFingerprint") ?? "none"
            )
        }
        
        let activeFingerprint = tlsFingerprint
        
        // Inject TLS Fingerprint if enabled (Do this before rule injection for cleaner logic)
        if activeFingerprint != "none" {
            cleanedProfile = injectFingerprint(into: cleanedProfile, fingerprint: activeFingerprint)
        }
        
        cleanedProfile = injectDynamicRules(into: cleanedProfile, tunEnabled: tunEnabled, mitmEnabled: mitmEnabled, mitmPort: mitmPort, bypassRules: bypassRules, localRules: localRules, mitmPortsString: mitmPortsString, mitmHosts: mitmHosts)
        
        // Check if subscription has its own dns/sniffer config (preserve subscription's optimized config)
        let profileHasDNS = cleanedProfile.lowercased().contains("\ndns:")
        let profileHasSniffer = cleanedProfile.lowercased().contains("\nsniffer:")
        
        // Build base Clash config with TUN setting (MainActor required for ClashConfig)
        let baseConfig = await MainActor.run {
            var clashConfig = ClashConfig(fromUserDefaults: true)
            if tunEnabled {
                clashConfig.enableTun = true
                clashConfig.skipDNS = profileHasDNS         // Skip our dns if subscription has one
                clashConfig.skipSniffer = profileHasSniffer // Skip our sniffer if subscription has one
            }
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
                ClashViewModel.shared.addLog("[Config] 📝 Writing config content (Preview lines 1-10):", level: .debug)
                let preview = finalConfig.components(separatedBy: "\n").prefix(10).joined(separator: "\n")
                ClashViewModel.shared.addLog(preview, level: .debug)
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
            "keep-alive-interval",
            "tcp-concurrent",
            "unified-delay",
            "global-client-fingerprint",
            "find-process-mode",
            "geodata-mode",
            "geodata-loader",
            "geox-url"
        ]
        
        // Multi-line block keys (need to remove entire block including children)
        // NOTE: Only remove TUN and profile - preserve subscription's DNS and sniffer for optimal performance
        let blockKeys = [
            "tun",      // Use our own TUN config (required for TUN mode control)
            "profile"   // Use our own profile config (required for node selection persistence)
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
    /// - localRules: User-defined raw rules (from Rules interface)
    /// - mitm: MITM interception rules (hijack configured ports/domains)
    /// - mitmHosts: Whitelist domains - only these will be routed to MITM
    nonisolated private func injectDynamicRules(into yaml: String, tunEnabled: Bool, mitmEnabled: Bool, mitmPort: Int, bypassRules: String, localRules: String, mitmPortsString: String, mitmHosts: String) -> String {
        print("[ConfigService] 🛠 Injecting Rules - Bypass: [\(bypassRules)], LocalRules: [\(localRules.count) chars], MITM Ports: [\(mitmPortsString)], MITM Hosts: [\(mitmHosts)], TUN: \(tunEnabled), MITM: \(mitmEnabled)")
        
        var result = yaml
        var rulesToInject: [String] = []  // No indentation yet
        
        // --- TLS Fingerprint Injection (Before rule processing) ---
        // This is handled by a separate helper, but we should make sure this method focuses on Rules.
        // Fingerprint injection is best done before rule injection to keep logic clean.
        
        // 1. Generate Local Overrides (Highest Priority)
        let localLines = localRules.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.hasPrefix("-") }
        
        rulesToInject.append(contentsOf: localLines)
        
        // 2. Generate Bypass Rules
        let bypassItems = bypassRules.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        
        for item in bypassItems {
            // Smart Parsing for macOS defaults
            if item == "10.*" {
                rulesToInject.append("- IP-CIDR,10.0.0.0/8,DIRECT")
            } else if item == "127.*" {
                rulesToInject.append("- IP-CIDR,127.0.0.0/8,DIRECT")
            } else if item == "192.168.*" {
                rulesToInject.append("- IP-CIDR,192.168.0.0/16,DIRECT")
            } else if item == "172.16.*" {
                rulesToInject.append("- IP-CIDR,172.16.0.0/12,DIRECT")
            } else if item.contains("/") {
                rulesToInject.append("- IP-CIDR,\(item),DIRECT")
            } else {
                let domain = item.replacingOccurrences(of: "*.", with: "")
                rulesToInject.append("- DOMAIN-SUFFIX,\(domain),DIRECT")
            }
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
                    rulesToInject.append("- AND,((DOMAIN-SUFFIX,\(domain)),(NOT,((PROCESS-NAME,Ares)))),MITM-Intercept")
                }
                print("[ConfigService] 📋 MITM Whitelist mode: \(whitelistDomains.count) domains will be intercepted")
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
                print("[ConfigService] 📋 MITM Port mode: intercepting ports \(validPorts)")
            }
            
            // Inject MITM Proxy Definition
            // Detect indentation for proxies
            var proxyIndent = "  " // Default 2 spaces
            if let range = result.range(of: "(?m)^\\s*proxies:.*$", options: .regularExpression) {
                proxyIndent = detectIndentation(in: result, after: range)
            }
            
            let mitmProxy = """
            \(proxyIndent)- name: MITM-Intercept
            \(proxyIndent)  type: http
            \(proxyIndent)  server: 127.0.0.1
            \(proxyIndent)  port: \(mitmPort)
            """
            
            // Regex to find "proxies:" at start of line
            if let range = result.range(of: "(?m)^\\s*proxies:.*$", options: .regularExpression) {
                result.insert(contentsOf: "\n" + mitmProxy, at: range.upperBound)
            } else {
                // If missing, append (using default 2 space indent)
                result.append("\nproxies:\n" + mitmProxy)
            }
        }
        
        print("[ConfigService] 📋 Generated \(rulesToInject.count) dynamic rules")
        
        // 4. Inject Rules Buffer at the top of "rules:"
        if !rulesToInject.isEmpty {
            // Detect indentation for rules
            var ruleIndent = "  "
            if let range = result.range(of: "(?m)^\\s*rules:.*$", options: .regularExpression) {
                ruleIndent = detectIndentation(in: result, after: range)
            }
            
            // Apply indentation to all rules
            let dynamicRulesBuffer = rulesToInject.map { ruleIndent + $0 }.joined(separator: "\n")
            
            // Regex to find "rules:" at start of line
            if let range = result.range(of: "(?m)^\\s*rules:.*$", options: .regularExpression) {
                result.insert(contentsOf: "\n" + dynamicRulesBuffer, at: range.upperBound)
            } else {
                 // If missing, append
                result.append("\nrules:\n" + dynamicRulesBuffer)
            }
        }
        
        return result
    }
    
    /// Helper to detect indentation of list items
    nonisolated private func detectIndentation(in yaml: String, after range: Range<String.Index>) -> String {
        let defaultIndent = "  "
        // Look at the next 20 lines max
        let substring = yaml[range.upperBound...]
        let lines = substring.components(separatedBy: .newlines).prefix(20)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            
            // If we find a list item, calculate its indentation
            if trimmed.hasPrefix("-") {
                let leadingSpaces = line.prefix(while: { $0 == " " }).count
                return String(repeating: " ", count: leadingSpaces)
            }
            
            // If we hit something that's NOT a list item (and not a comment/empty), 
            // the list might be empty or formatted differently. Stop.
            // Exception: sub-keys (e.g. key: value). But we are looking for list items of the parent.
            if !trimmed.hasPrefix("-") && trimmed.contains(":") {
                 // Might be end of section
                 break
            }
        }
        return defaultIndent
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

    
    /// Inject TLS Fingerprint into proxy definitions (Robust Flow & Block support)
    nonisolated private func injectFingerprint(into yaml: String, fingerprint: String) -> String {
        print("[ConfigService] 🕵️ Injecting TLS Fingerprint (Enhanced): \(fingerprint)")
        
        let lines = yaml.components(separatedBy: .newlines)
        var result: [String] = []
        var count = 0
        
        // Target protocols for fingerprint injection
        let targets = ["ss", "vmess", "vless", "trojan", "hysteria", "hysteria2", "tuic"]
        
        // State Machine
        var inProxiesSection = false
        var proxyBuffer: [String] = []
        
        // Helper: Process and flush the current buffered proxy item
        func flushBuffer() {
            guard !proxyBuffer.isEmpty else { return }
            
            let joined = proxyBuffer.joined(separator: "\n")
            let lowerJoined = joined.lowercased()
            
            // Check if this proxy block contains a target protocol
            var isTarget = false
            for t in targets {
                // Check for "type: t" or "type: "t""
                if lowerJoined.contains("type: \(t)") || lowerJoined.contains("type: \"\(t)\"") {
                    isTarget = true
                    break
                }
            }
            
            // Check if fingerprint already exists
            let hasFingerprint = lowerJoined.contains("client-fingerprint")
            
            if isTarget && !hasFingerprint {
                // Determine injection strategy
                var injected = false
                
                // Strategy A: Flow Style (Single line with braces)
                // If buffer is 1 line and has braces
                if proxyBuffer.count == 1 && proxyBuffer[0].contains("{") && proxyBuffer[0].contains("}") {
                    var line = proxyBuffer[0]
                    if let lastBrace = line.lastIndex(of: "}") {
                        line.insert(contentsOf: ", client-fingerprint: \(fingerprint)", at: lastBrace)
                        result.append(line)
                        count += 1
                        injected = true
                    }
                }
                
                // Strategy B: Block Style (Multi-line)
                if !injected {
                    // Find the "type:" line and inject after it
                    for line in proxyBuffer {
                        result.append(line)
                        
                        let trimmed = line.trimmingCharacters(in: .whitespaces).lowercased()
                        if !injected && (trimmed.hasPrefix("type:") || trimmed.hasPrefix("- type:")) {
                            // Calculate indentation
                            let indent = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
                            var padding = indent
                            
                            // If line starts with "-", usually subsequent keys are indented by 2 more spaces
                            if line.trimmingCharacters(in: .whitespaces).hasPrefix("-") {
                                padding += "  "
                            }
                            
                            result.append("\(padding)client-fingerprint: \(fingerprint)")
                            
                            count += 1
                            injected = true
                        }
                    }
                }
            } else {
                // No injection needed, passthrough
                result.append(contentsOf: proxyBuffer)
            }
            
            proxyBuffer.removeAll()
        }
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // 1. Detect Section Headers
            // Root keys have no indentation (or minimal if messy) and end with colon.
            // Be careful not to trigger on comments or empty lines.
            if !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                let isRootKey = !line.hasPrefix(" ") && !line.hasPrefix("\t") && trimmed.hasSuffix(":")
                
                if isRootKey {
                    if inProxiesSection {
                        flushBuffer() // Flush last proxy item
                        inProxiesSection = false
                    }
                    
                    if trimmed == "proxies:" {
                        inProxiesSection = true
                        result.append(line)
                        continue
                    }
                }
            }
            
            // 2. Proxies Section Logic
            if inProxiesSection {
                // Check if it's a new list item
                if trimmed.hasPrefix("-") {
                    flushBuffer() // Flush previous proxy
                    proxyBuffer.append(line)
                } else {
                    // Continuation or Comment?
                    if proxyBuffer.isEmpty {
                        // Random noise in proxies section
                        result.append(line)
                    } else {
                        proxyBuffer.append(line)
                    }
                }
            } else {
                // Passthrough for non-proxy lines
                result.append(line)
            }
        }
        
        flushBuffer() // Final flush if ended in proxy section
        
        print("[ConfigService] ✅ Injected fingerprint into \(count) nodes (Robust Mode)")
        return result.joined(separator: "\n")
    }
}
