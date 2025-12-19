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
        let cleanedProfile = removeConflictingKeys(from: profileContent)
        
        // Build base Clash config with TUN setting (MainActor required for ClashConfig)
        let baseConfig = await MainActor.run {
            var clashConfig = ClashConfig(fromUserDefaults: true)
            clashConfig.enableTun = tunEnabled
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
    nonisolated private func removeConflictingKeys(from yaml: String) -> String {
        let conflictingKeys = [
            "mixed-port",
            "socks-port",
            "port",
            "mode",
            "log-level",
            "allow-lan",
            "ipv6",
            "external-controller",
            "secret",
            "tun"  // Use our own TUN config
        ]
        
        let lines = yaml.components(separatedBy: .newlines)
        var result: [String] = []
        var removedCount = 0
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lower = trimmed.lowercased()
            
            // Check if line starts with a conflicting key
            var isConflicting = false
            for key in conflictingKeys {
                // Check if line starts with key (ignoring indentation)
                // Robust check: key + ":" or just key (for section headers like 'tun:')
                if lower.hasPrefix(key + ":") || lower == key || lower.hasPrefix(key + " :") {
                    isConflicting = true
                    removedCount += 1
                    break
                }
            }
            
            if !isConflicting {
                result.append(line)
            }
        }
        
        return result.joined(separator: "\n")
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
