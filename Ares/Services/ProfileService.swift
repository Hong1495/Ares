import Foundation
import Combine

/// Service for managing Clash profiles
class ProfileService: ObservableObject {
    static let shared = ProfileService()
    
    @Published var profiles: [Profile] = []
    @Published var activeProfileID: UUID?
    
    private let profilesDir: URL
    private let profilesMetadataFile: URL
    
    private init() {
        // Setup directories
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let aresDir = appSupport.appendingPathComponent("Ares")
        self.profilesDir = aresDir.appendingPathComponent("profiles")
        self.profilesMetadataFile = aresDir.appendingPathComponent("profiles.json")
        
        // Create directories if needed
        try? FileManager.default.createDirectory(at: profilesDir, withIntermediateDirectories: true)
        
        // Load profiles asynchronously on next run loop
        Task { @MainActor in
            self.loadProfiles()
        }
    }
    
    /// Load profiles from disk
    func loadProfiles() {
        guard FileManager.default.fileExists(atPath: profilesMetadataFile.path) else {
            Task { @MainActor in
                ClashViewModel.shared.addLog("[ProfileService] ⚠️ No profiles.json found, starting fresh")
            }
            return
        }
        
        do {
            let data = try Data(contentsOf: profilesMetadataFile)
            let decoded = try JSONDecoder().decode([Profile].self, from: data)
            self.profiles = decoded
            
            // Auto-select first profile if none active
            if activeProfileID == nil, let first = profiles.first {
                activeProfileID = first.id
            }
            
            Task { @MainActor in
                ClashViewModel.shared.addLog("[ProfileService] ✅ Loaded \(self.profiles.count) profiles")
                if let active = self.activeProfile {
                    ClashViewModel.shared.addLog("[ProfileService] 🔹 Active Profile: \(active.name)")
                } else {
                    ClashViewModel.shared.addLog("[ProfileService] ⚠️ No active profile selected")
                }
            }
        } catch {
            Task { @MainActor in
                ClashViewModel.shared.addLog("[ProfileService] ❌ Failed to load profiles: \(error)")
            }
            print("[ProfileService] Failed to load profiles: \(error)")
        }
    }
    
    /// Save profiles to disk
    func saveProfiles() {
        do {
            let data = try JSONEncoder().encode(profiles)
            try data.write(to: profilesMetadataFile)
            print("[ProfileService] Saved \(profiles.count) profiles")
        } catch {
            print("[ProfileService] Failed to save profiles: \(error)")
        }
    }
    
    /// Add a new remote profile
    func addRemoteProfile(name: String, url: URL) async throws {
        var profile = Profile.remote(name: name, url: url)
        
        // Download profile content
        try await updateProfile(&profile)
        
        // Add to list
        profiles.append(profile)
        
        // Auto-select if first profile OR always activate new profile for better UX
        let shouldActivate = profiles.count == 1 || activeProfileID == nil
        if shouldActivate {
            activeProfileID = profile.id
        }
        
        saveProfiles()
        
        Task { @MainActor in
            ClashViewModel.shared.addLog("[ProfileService] ✅ Added remote profile: \(name)")
            
            // If this is the active profile, reload Clash
            if shouldActivate {
                ClashViewModel.shared.addLog("[ProfileService] 🔄 Activating new profile...")
                await reloadClashWithCurrentProfile()
            }
        }
    }
    
    /// Add a local profile
    func addLocalProfile(name: String, fileURL: URL) throws {
        // Copy file to profiles directory
        let filename = "\(UUID().uuidString).yaml"
        let destination = profilesDir.appendingPathComponent(filename)
        try FileManager.default.copyItem(at: fileURL, to: destination)
        
        let profile = Profile.local(name: name, path: destination)
        profiles.append(profile)
        
        // Auto-select if first profile OR no active profile
        let shouldActivate = profiles.count == 1 || activeProfileID == nil
        if shouldActivate {
            activeProfileID = profile.id
        }
        
        saveProfiles()
        
        Task { @MainActor in
            ClashViewModel.shared.addLog("[ProfileService] ✅ Added local profile: \(name)")
            
            // If this is the active profile, reload Clash
            if shouldActivate {
                ClashViewModel.shared.addLog("[ProfileService] 🔄 Activating new profile...")
                await reloadClashWithCurrentProfile()
            }
        }
    }
    
    /// Update a remote profile by downloading latest content
    func updateProfile(_ profile: inout Profile) async throws {
        guard profile.type == .remote, let url = profile.url else {
            throw NSError(domain: "ProfileService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not a remote profile"])
        }
        
        print("[ProfileService] Downloading profile from: \(url)")
        
        // Download profile with Clash User-Agent
        var request = URLRequest(url: url)
        request.setValue("Clash/1.0 (Ares; macOS)", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Parse subscription info from headers
        if let httpResponse = response as? HTTPURLResponse {
            profile.subscriptionInfo = parseSubscriptionInfo(from: httpResponse)
        }
        
        // Fallback: Parse from YAML content if header info is missing
        if profile.subscriptionInfo == nil || profile.subscriptionInfo?.total == 0 {
            if let content = String(data: data, encoding: .utf8) {
                if let info = parseSubscriptionInfo(fromContent: content) {
                    profile.subscriptionInfo = info
                }
            }
        }
        
        // Save to file
        let filename = "\(profile.id.uuidString).yaml"
        let destination = profilesDir.appendingPathComponent(filename)
        try data.write(to: destination)
        
        // Update profile
        profile.path = destination
        profile.lastUpdated = Date()
        
        print("[ProfileService] Profile updated: \(profile.name)")
    }
    
    /// Update a remote profile by re-downloading
    func updateProfile(id: UUID) async throws {
        guard let index = profiles.firstIndex(where: { $0.id == id }),
              case .remote = profiles[index].type,
              let url = profiles[index].url else {
            throw NSError(domain: "ProfileService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Profile not found or not remote"])
        }
        
        print("[ProfileService] Updating profile: \(profiles[index].name)")
        
        // Download updated content with Clash User-Agent
        var request = URLRequest(url: url)
        request.setValue("Clash/1.0 (Ares; macOS)", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Parse subscription info from headers
        if let httpResponse = response as? HTTPURLResponse {
            profiles[index].subscriptionInfo = parseSubscriptionInfo(from: httpResponse)
        }
        
        guard let content = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "ProfileService", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid profile content"])
        }
        
        // Fallback: Parse from YAML content if header info is missing
        if profiles[index].subscriptionInfo == nil || profiles[index].subscriptionInfo?.total == 0 {
            if let info = parseSubscriptionInfo(fromContent: content) {
                profiles[index].subscriptionInfo = info
            }
        }
        
        // Save to existing path
        if let path = profiles[index].path {
            try content.write(to: path, atomically: true, encoding: .utf8)
        } else {
            // Create path if missing
            let filename = "\(id.uuidString).yaml"
            let path = profilesDir.appendingPathComponent(filename)
            try content.write(to: path, atomically: true, encoding: .utf8)
            profiles[index].path = path
        }
        
        // Update timestamp
        profiles[index].lastUpdated = Date()
        
        // Save metadata
        saveProfiles()
        
        print("[ProfileService] Updated profile: \(profiles[index].name)")
    }
    
    /// Delete a profile
    func deleteProfile(id: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        
        let profile = profiles[index]
        
        // Delete file if exists
        if let path = profile.path {
            try? FileManager.default.removeItem(at: path)
        }
        
        // Remove from list
        profiles.remove(at: index)
        
        // Clear active if deleted
        if activeProfileID == id {
            activeProfileID = profiles.first?.id
        }
        
        saveProfiles()
        print("[ProfileService] Deleted profile: \(profile.name)")
    }
    
    /// Get the active profile
    var activeProfile: Profile? {
        guard let id = activeProfileID else { return nil }
        return profiles.first(where: { $0.id == id })
    }
    
    /// Set active profile and reload Clash with new configuration
    func setActiveProfile(id: UUID) {
        guard activeProfileID != id else { return } // No-op if already active
        
        activeProfileID = id
        saveProfiles()
        
        // Find the new profile name for logging
        let profileName = profiles.first(where: { $0.id == id })?.name ?? "Unknown"
        
        Task { @MainActor in
            ClashViewModel.shared.addLog("[ProfileService] 🔄 Switching to profile: \(profileName)")
            
            // Rebuild config and restart Clash
            await reloadClashWithCurrentProfile()
        }
    }
    
    /// Reload Clash with the current active profile
    @MainActor
    func reloadClashWithCurrentProfile() async {
        let tunEnabled = AppState.shared.tunEnabled
        
        ClashViewModel.shared.addLog("[ProfileService] 📝 Rebuilding configuration...")
        
        do {
            // 1. Rebuild config with new profile
            try await ConfigService.shared.buildConfig(tunEnabled: tunEnabled)
            
            // 2. Restart Clash to apply new config
            ClashViewModel.shared.addLog("[ProfileService] 🔄 Restarting Clash with new profile...")
            await ClashViewModel.shared.restart()
            
            // 3. Wait for API to be ready
            let isReady = await ClashController.shared.waitForAPIReady(timeout: 5.0)
            if isReady {
                ClashViewModel.shared.addLog("[ProfileService] ✅ Profile switch completed")
                
                // 4. Refresh proxies and rules
                try? await ClashController.shared.fetchProxiesData()
                try? await ClashController.shared.fetchRules()
            } else {
                ClashViewModel.shared.addLog("[ProfileService] ⚠️ Clash API not ready after restart")
            }
        } catch {
            ClashViewModel.shared.addLog("[ProfileService] ❌ Failed to reload: \(error.localizedDescription)")
        }
    }
    
    /// Parse subscription info from HTTP headers
    private func parseSubscriptionInfo(from response: HTTPURLResponse) -> SubscriptionInfo? {
        if let userInfo = response.value(forHTTPHeaderField: "subscription-userinfo") {
            Task { @MainActor in
                ClashViewModel.shared.addLog("[ProfileService] 📡 Subscription Info Header: \(userInfo)")
            }
            return parseSubscriptionInfo(fromString: userInfo)
        }
        return nil
    }
    
    /// Parse subscription info from YAML content (look for comments at the top)
    private func parseSubscriptionInfo(fromContent content: String) -> SubscriptionInfo? {
        let lines = content.components(separatedBy: .newlines)
        // Only check first 30 lines for performance
        for line in lines.prefix(30) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") {
                let comment = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
                if comment.lowercased().localizedCaseInsensitiveContains("subscription-userinfo:") {
                    let parts = comment.components(separatedBy: ":")
                    if parts.count >= 2 {
                        let infoPart = parts[1...].joined(separator: ":").trimmingCharacters(in: .whitespaces)
                        return parseSubscriptionInfo(fromString: infoPart)
                    }
                } else if comment.lowercased().contains("upload=") && comment.lowercased().contains("total=") {
                    // Direct key=value support without the prefix
                    return parseSubscriptionInfo(fromString: comment)
                }
            }
        }
        return nil
    }
    
    /// Robust number parsing (handles floats like 123.45)
    private func parseLong(_ value: String) -> Int64 {
        let cleaned = value.trimmingCharacters(in: CharacterSet.decimalDigits.inverted.subtracting(.init(charactersIn: ".")))
        if let long = Int64(cleaned) {
            return long
        }
        if let double = Double(cleaned) {
            return Int64(double)
        }
        return 0
    }
    
    private func parseSubscriptionInfo(fromString userInfo: String) -> SubscriptionInfo? {
        var upload: Int64 = 0
        var download: Int64 = 0
        var total: Int64 = 0
        var expire: Date? = nil
        
        let components = userInfo.components(separatedBy: ";")
        for component in components {
            let part = component.trimmingCharacters(in: .whitespaces)
            let kv = part.components(separatedBy: "=")
            if kv.count == 2 {
                let key = kv[0].lowercased().trimmingCharacters(in: .whitespaces)
                let value = kv[1].trimmingCharacters(in: .whitespaces)
                
                switch key {
                case "upload": upload = parseLong(value)
                case "download": download = parseLong(value)
                case "total": total = parseLong(value)
                case "expire":
                    if let seconds = Double(value) {
                        expire = Date(timeIntervalSince1970: seconds)
                    }
                default: break
                }
            }
        }
        
        if upload == 0 && download == 0 && total == 0 { return nil }
        return SubscriptionInfo(upload: upload, download: download, total: total, expire: expire)
    }
}
