import Foundation
import Combine

/// Service for managing Clash profiles
class ProfileService: ObservableObject {
    static let shared = ProfileService()

    @Published var profiles: [Profile] = []
    @Published var activeProfileID: UUID?
    @Published var isSwitchingProfile: Bool = false

    private let profilesDir: URL
    private let profilesMetadataFile: URL

    /// Dedicated URLSession that bypasses system proxy for subscription downloads.
    /// This prevents the chicken-and-egg problem where the subscription URL itself
    /// gets routed through a proxy/TUN that depends on the subscription being loaded.
    private lazy var directURLSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.connectionProxyDictionary = [:]  // Bypass ALL system proxies
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()

    private init() {
        // Setup directories
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let aresDir = appSupport.appendingPathComponent("Ares")
        self.profilesDir = aresDir.appendingPathComponent("profiles")
        self.profilesMetadataFile = aresDir.appendingPathComponent("profiles.json")

        // Create directories if needed
        try? FileManager.default.createDirectory(at: profilesDir, withIntermediateDirectories: true)

        // Load profiles synchronously to ensure they're ready before Clash starts
        // This is critical for startup timing - Clash needs the active profile to build config
        self.loadProfiles()
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

            // Restore active profile ID from UserDefaults
            if let savedIDString = UserDefaults.standard.string(forKey: DefaultsKeys.activeProfileID),
               let savedID = UUID(uuidString: savedIDString),
               profiles.contains(where: { $0.id == savedID }) {
                activeProfileID = savedID
            } else if let first = profiles.first {
                // Fallback to first profile if saved ID is invalid
                activeProfileID = first.id
            }

            Task { @MainActor in
                ClashViewModel.shared.addLog("[ProfileService] ✅ Loaded \(self.profiles.count) profiles")
                if self.activeProfile != nil {
                    ClashViewModel.shared.addLog("[ProfileService] 🔹 Active profile restored", level: .debug)
                } else {
                    ClashViewModel.shared.addLog("[ProfileService] ⚠️ No active profile selected")
                }
            }
        } catch {
            Task { @MainActor in
                ClashViewModel.shared.addLog("[ProfileService] ❌ Failed to load profiles: \(error)")
            }
        }
    }

    /// Save profiles to disk
    func saveProfiles() {
        do {
            let data = try JSONEncoder().encode(profiles)
            try data.write(to: profilesMetadataFile)

            // Also persist active profile ID
            if let activeID = activeProfileID {
                UserDefaults.standard.set(activeID.uuidString, forKey: DefaultsKeys.activeProfileID)
            }
        } catch {
            Task { @MainActor in
                ClashViewModel.shared.addLog("[ProfileService] Failed to save profiles: \(error)", level: .debug)
            }
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
            ClashViewModel.shared.addLog("[ProfileService] ✅ Added remote profile")

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
            ClashViewModel.shared.addLog("[ProfileService] ✅ Added local profile")

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

        let finalUrl = appendCompatibilityFlags(to: url)

        // Unified User-Agent for maximum compatibility
        let userAgent = "ClashMeta/1.31.0 Enforce (Ares; macOS)"
        var request = URLRequest(url: finalUrl)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await directURLSession.data(for: request)

        // Parse subscription info from headers
        if let httpResponse = response as? HTTPURLResponse {
            profile.subscriptionInfo = parseSubscriptionInfo(from: httpResponse)
        }

        // Destination path
        let filename = "\(profile.id.uuidString).yaml"
        let destination = profilesDir.appendingPathComponent(filename)

        // Fallback: Parse from YAML content if header info is missing
        if profile.subscriptionInfo == nil || profile.subscriptionInfo?.total == 0 {
            if let content = String(data: data, encoding: .utf8) {
                if let info = parseSubscriptionInfo(fromContent: content) {
                    profile.subscriptionInfo = info
                }

                // Check if content needs conversion (Base64 -> YAML)
                if let converted = SubscriptionConverter.convert(content: content) {
                    // Use converted content
                    try converted.write(to: destination, atomically: true, encoding: .utf8)

                    // Update profile path and timestamp
                    profile.path = destination
                    profile.lastUpdated = Date()

                    return
                }
            }
        }

        // Save to file
        try data.write(to: destination)

        // Update profile
        profile.path = destination
        profile.lastUpdated = Date()
    }

    /// Update a remote profile by re-downloading
    func updateProfile(id: UUID) async throws {
        guard let index = profiles.firstIndex(where: { $0.id == id }),
              case .remote = profiles[index].type,
              let url = profiles[index].url else {
            throw NSError(domain: "ProfileService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Profile not found or not remote"])
        }

        let isActive = activeProfileID == id

        let finalUrl = appendCompatibilityFlags(to: url)
        await MainActor.run {
            ClashViewModel.shared.addLog("[ProfileService] 🔄 Updating profile")
        }

        // Unified User-Agent for maximum compatibility
        let userAgent = "ClashMeta/1.31.0 Enforce (Ares; macOS)"
        var request = URLRequest(url: finalUrl)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await directURLSession.data(for: request)

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

        // Check if content needs conversion (Base64 -> YAML)
        var finalContent = content
        if let converted = SubscriptionConverter.convert(content: content) {
            await MainActor.run {
                ClashViewModel.shared.addLog("[ProfileService] 🔄 Automatically converted subscription format")
            }
            finalContent = converted
        }

        // Save to existing path (use finalContent, not content!)
        if let path = profiles[index].path {
            try finalContent.write(to: path, atomically: true, encoding: .utf8)
        } else {
            // Create path if missing
            let filename = "\(id.uuidString).yaml"
            let path = profilesDir.appendingPathComponent(filename)
            try finalContent.write(to: path, atomically: true, encoding: .utf8)
            profiles[index].path = path
        }

        // Update timestamp
        profiles[index].lastUpdated = Date()

        // Save metadata
        saveProfiles()

        await MainActor.run {
            ClashViewModel.shared.addLog("[ProfileService] ✅ Updated profile")
        }

        // If this is the active profile, reload Clash to apply changes
        if isActive {
            await MainActor.run {
                ClashViewModel.shared.addLog("[ProfileService] 🔄 Reloading Clash with updated profile...")
            }
            await reloadClashWithCurrentProfile()
        }
    }

    /// Edit profile metadata (Name, URL)
    func editProfile(id: UUID, name: String, urlString: String) throws {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }

        var profile = profiles[index]
        profile.name = name

        // Only update URL for remote profiles
        if profile.type == .remote {
            if let newURL = URL(string: urlString) {
                profile.url = newURL
            } else {
                throw NSError(domain: "ProfileService", code: 5, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
            }
        }

        profiles[index] = profile
        saveProfiles()

        Task { @MainActor in
            ClashViewModel.shared.addLog("[ProfileService] ✏️ Edited profile")
        }
    }

    /// Read the raw content of a profile
    func readProfileContent(id: UUID) async throws -> String {
        guard let profile = profiles.first(where: { $0.id == id }),
              let path = profile.path else {
            throw NSError(domain: "ProfileService", code: 10, userInfo: [NSLocalizedDescriptionKey: "Profile or path not found"])
        }

        return try String(contentsOf: path, encoding: .utf8)
    }

    /// Update the raw content of a profile
    func updateProfileContent(id: UUID, content: String) async throws {
        guard let index = profiles.firstIndex(where: { $0.id == id }),
              let path = profiles[index].path else {
            throw NSError(domain: "ProfileService", code: 11, userInfo: [NSLocalizedDescriptionKey: "Profile or path not found"])
        }

        // Write content to file
        try content.write(to: path, atomically: true, encoding: .utf8)

        // Update metadata (lastUpdated)
        profiles[index].lastUpdated = Date()
        saveProfiles()

        Task { @MainActor in
            ClashViewModel.shared.addLog("[ProfileService] 📝 Raw profile content updated")

            // If this is the active profile, reload Clash
            if self.activeProfileID == id {
                ClashViewModel.shared.addLog("[ProfileService] 🔄 Reloading Clash to apply manual changes...")
                await self.reloadClashWithCurrentProfile()
            }
        }
    }

    /// Delete a profile
    func deleteProfile(id: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }

        let profile = profiles[index]
        let wasActive = activeProfileID == id

        // Delete file if exists
        if let path = profile.path {
            try? FileManager.default.removeItem(at: path)
        }

        // Remove from list
        profiles.remove(at: index)

        // Clear active if deleted and switch to next available
        if wasActive {
            activeProfileID = profiles.first?.id
        }

        saveProfiles()

        Task { @MainActor in
            ClashViewModel.shared.addLog("[ProfileService] 🗑️ Deleted profile")

            // If we deleted the active profile, we need to reload Clash
            if wasActive {
                if profiles.first != nil {
                    ClashViewModel.shared.addLog("[ProfileService] 🔄 Switching to next profile")
                    await reloadClashWithCurrentProfile()
                } else {
                    // No profiles left, stop Clash
                    ClashViewModel.shared.addLog("[ProfileService] ⚠️ No profiles remaining, stopping Clash...")
                    await ClashViewModel.shared.stop()
                }
            }
        }
    }

    /// Get the active profile
    var activeProfile: Profile? {
        guard let id = activeProfileID else { return nil }
        return profiles.first(where: { $0.id == id })
    }

    /// Set active profile and reload Clash with new configuration
    func setActiveProfile(id: UUID) {
        guard activeProfileID != id else { return } // No-op if already active
        guard !isSwitchingProfile else {
            ClashViewModel.shared.addLog("[ProfileService] ⚠️ Profile switch already in progress", level: .debug)
            return
        }

        // Mark switching state to prevent multiple rapid switches
        isSwitchingProfile = true

        // Update the active profile ID
        activeProfileID = id
        saveProfiles()

        Task { @MainActor in
            ClashViewModel.shared.addLog("[ProfileService] 🔄 Switching profile")

            // Rebuild config and restart Clash
            await reloadClashWithCurrentProfile()

            // Clear switching state
            isSwitchingProfile = false

            // Notify observers that profile has changed (force UI refresh)
            objectWillChange.send()
        }
    }

    /// Reload Clash with the current active profile
    @MainActor
    func reloadClashWithCurrentProfile() async {
        let tunEnabled = AppState.shared.tunEnabled
        let systemProxyEnabled = AppState.shared.systemProxyEnabled

        ClashViewModel.shared.addLog("[ProfileService] 📝 Rebuilding configuration (TUN=\(tunEnabled))...")

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

                // 4. Force refresh proxies and rules
                // Clear old state first to avoid UI confusing old data with new
                await MainActor.run {
                    ClashController.shared.proxyGroups = []
                    ClashController.shared.proxyNodes = [:]
                    ClashController.shared.rules = []
                }

                try? await Task.sleep(nanoseconds: 500_000_000) // Small delay for core to initialize mappings

                do {
                    try await ClashController.shared.fetchProxiesData()
                    try await ClashController.shared.fetchRules()
                    ClashViewModel.shared.addLog("[ProfileService] 📡 Refreshed UI data for new profile")
                } catch {
                     ClashViewModel.shared.addLog("[ProfileService] ⚠️ Failed to fetch fresh data: \(error)")
                }

                // 5. CRITICAL: Restore system proxy if it was enabled
                // This ensures proxy continues to work after profile switch
                // In TUN mode, enableSystemProxy is still needed for DNS hijacking in some configurations
                if systemProxyEnabled {
                    ClashViewModel.shared.addLog("[ProfileService] 🌐 Restoring system proxy...")
                    await AppState.shared.enableSystemProxy()
                }

                // 6. Log TUN mode status
                if tunEnabled {
                    ClashViewModel.shared.addLog("[ProfileService] 🛡️ TUN mode active, profile switch complete")
                }
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
                ClashViewModel.shared.addLog("[ProfileService] 📡 Subscription info detected", level: .debug)
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

    /// Automatically append compatibility flags for common panels
    private func appendCompatibilityFlags(to url: URL) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)
        var queryItems = components?.queryItems ?? []

        // If it's a subscription URL and doesn't have a flag, add flag=clashmeta
        // This forces panels like V2Board to return YAML with full protocol support
        if url.path.contains("subscribe") || url.absoluteString.contains("/api/v1/client/subscribe") {
            if !queryItems.contains(where: { $0.name == "flag" }) {
                queryItems.append(URLQueryItem(name: "flag", value: "clashmeta"))
                components?.queryItems = queryItems
                if let newUrl = components?.url {
                    return newUrl
                }
            }
        }

        return url
    }
}
