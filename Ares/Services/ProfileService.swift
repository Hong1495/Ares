import Foundation
import Combine
import SubscriptionKit

/// Service for managing Clash profiles
@MainActor
class ProfileService: ObservableObject {
    static let shared = ProfileService()

    @Published var profiles: [Profile] = []
    @Published var activeProfileID: UUID?
    @Published var isSwitchingProfile: Bool = false

    @Published private var nodeSelections: NodeSelectionPlan = {
        guard let data = UserDefaults.standard.data(forKey: "profileNodeSelections"),
              let plan = try? JSONDecoder().decode(NodeSelectionPlan.self, from: data) else { return NodeSelectionPlan() }
        return plan
    }()

    var activeProfileRevision: String {
        guard let profile = activeProfile else { return "" }
        return "\(profile.id)|\(profile.path?.path ?? "")|\(profile.lastUpdated?.timeIntervalSince1970 ?? 0)"
    }

    func savedNode(group: String) -> String? {
        guard let id = activeProfileID else { return nil }
        return nodeSelections.choices(for: id)[group]
    }

    func selectNode(group: ProxyGroup, node: String) async throws {
        guard group.supportsManualSelection, group.all.contains(node), let id = activeProfileID else {
            throw NSError(domain: "Selection", code: 4, userInfo: [NSLocalizedDescriptionKey: "This node cannot be selected in the current group."])
        }
        let vm = ClashViewModel.shared
        guard !vm.isToggling, AppState.shared.beginOperation("Selecting Node") else {
            throw NSError(domain: "Selection", code: 1, userInfo: [NSLocalizedDescriptionKey: "Wait for the current operation to finish."])
        }
        defer { AppState.shared.finishOperation() }
        if vm.isRunning {
            guard vm.appliedProfileRevision == activeProfileRevision else {
                throw NSError(domain: "Selection", code: 2, userInfo: [NSLocalizedDescriptionKey: "Apply the selected subscription before changing the running node."])
            }
            try await ClashController.shared.selectProxy(group: group.name, proxy: node)
        }
        nodeSelections.select(profile: id, group: group.name, node: node)
        UserDefaults.standard.set(try JSONEncoder().encode(nodeSelections), forKey: "profileNodeSelections")
    }

    func clearNodeSelection(group: ProxyGroup) async throws {
        guard group.type == "URLTest" || group.type == "Fallback", let id = activeProfileID else { return }
        let vm = ClashViewModel.shared
        guard !vm.isToggling, AppState.shared.beginOperation("Resetting Node Selection") else {
            throw NSError(domain: "Selection", code: 1, userInfo: [NSLocalizedDescriptionKey: "Wait for the current operation to finish."])
        }
        defer { AppState.shared.finishOperation() }
        if vm.isRunning {
            guard vm.appliedProfileRevision == activeProfileRevision else {
                throw NSError(domain: "Selection", code: 2, userInfo: [NSLocalizedDescriptionKey: "Apply the selected subscription before changing the running node."])
            }
            try await ClashController.shared.clearProxySelection(group: group.name)
        }
        nodeSelections.clear(profile: id, group: group.name)
        UserDefaults.standard.set(try JSONEncoder().encode(nodeSelections), forKey: "profileNodeSelections")
    }

    func restoreNodeSelections() async throws {
        guard let id = activeProfileID else { return }
        let controller = ClashController.shared
        try await controller.fetchProxiesData()
        try await NodeSelectionPlan.restore(nodeSelections.choices(for: id), groups: controller.proxyGroups, reset: { group in
            try await controller.clearProxySelection(group: group)
        }) { group, node in
            try await controller.selectProxy(group: group, proxy: node)
        }
    }

    private var updateRevisions = ProfileUpdateRevisions()
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
            try data.write(to: profilesMetadataFile, options: .atomic)

            // Also persist active profile ID
            if let activeID = activeProfileID {
                UserDefaults.standard.set(activeID.uuidString, forKey: DefaultsKeys.activeProfileID)
            } else {
                UserDefaults.standard.removeObject(forKey: DefaultsKeys.activeProfileID)
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

        // Keep the current profile when adding additional subscriptions.
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

    private func downloadProfile(_ profile: Profile) async throws -> (String, SubscriptionInfo?, Bool) {
        guard profile.type == .remote, let url = profile.url, ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { throw URLError(.badURL) }
        var request = URLRequest(url: appendCompatibilityFlags(to: url))
        request.setValue("ClashMeta/1.31.0 Enforce (Ares; macOS)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await directURLSession.data(for: request)
        var needsResources = false
        let content = try await SubscriptionPayload.prepare(data: data, response: response) { candidate in
            let result = try await self.validateProfileContent(candidate)
            needsResources = result.needsResources
            return result.valid
        }
        let header = (response as? HTTPURLResponse).flatMap { parseSubscriptionInfo(from: $0) }
        let info = (header?.total ?? 0) > 0 ? header : (parseSubscriptionInfo(fromContent: content) ?? header)
        return (content, info, needsResources)
    }

    private func validateProfileContent(_ content: String) async throws -> (valid: Bool, needsResources: Bool) {
        // Full mihomo parsing happens only on an isolated candidate, before replacement.
        // Development tests inject a validator and never execute this production path.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Ares-validation-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try content.write(to: directory.appendingPathComponent("config.yaml"), atomically: true, encoding: .utf8)
        // Preserve offline import when only a remote GeoIP/rule resource is unavailable.
        // Actual activation still requires full validation before changing the running core.
        guard let snapshot = try? SubscriptionSnapshot.parse(content) else { return (false, false) }
        guard !snapshot.nodes.isEmpty || snapshot.providerCount > 0 else { return (false, false) }
        for filename in ["Country.mmdb", "geoip.dat", "geosite.dat", "ASN.mmdb"] {
            for mode in [false, true] {
                let resource = await ConfigService.shared.getConfigDir(tunEnabled: mode).appendingPathComponent(filename)
                if FileManager.default.fileExists(atPath: resource.path) {
                    try? FileManager.default.copyItem(at: resource, to: directory.appendingPathComponent(filename))
                    break
                }
            }
        }
        do { return (try await CoreManager.shared.validateConfigStrict(configDir: directory), false) }
        catch ConfigurationValidationFailure.resourcesUnavailable {
            ClashViewModel.shared.addLog("[Subscription] Saved for offline use; rule resources must be available before activation.", level: .warning)
            return (true, true)
        }
    }

    func updateProfile(_ profile: inout Profile) async throws {
        let (content, info, needsResources) = try await downloadProfile(profile)
        let destination = profilesDir.appendingPathComponent("\(profile.id.uuidString).yaml")
        try content.write(to: destination, atomically: true, encoding: .utf8)
        profile.path = destination
        profile.subscriptionInfo = info
        profile.needsRuleResources = needsResources
        profile.lastUpdated = Date()
    }

    func updateProfile(id: UUID) async throws {
        guard let profile = profiles.first(where: { $0.id == id }) else { throw URLError(.fileDoesNotExist) }
        let revision = updateRevisions.begin(id)
        let (content, info, needsResources) = try await downloadProfile(profile)
        try Task.checkCancellation()
        // Resolve the index AFTER all suspension points. Delete/edit/newer refresh invalidates this response.
        guard !ClashViewModel.shared.isToggling, updateRevisions.isCurrent(revision, for: id),
              let index = profiles.firstIndex(where: { $0.id == id }), profiles[index].url == profile.url else { throw CancellationError() }
        let destination = profiles[index].path ?? profilesDir.appendingPathComponent("\(id.uuidString).yaml")
        let previousData = try? Data(contentsOf: destination)
        let previousProfiles = profiles
        do {
            try content.write(to: destination, atomically: true, encoding: .utf8)
            profiles[index].path = destination
            profiles[index].subscriptionInfo = info
            profiles[index].needsRuleResources = needsResources
            profiles[index].lastUpdated = Date()
            try JSONEncoder().encode(profiles).write(to: profilesMetadataFile, options: .atomic)
        } catch {
            profiles = previousProfiles
            if let previousData { try previousData.write(to: destination, options: .atomic) }
            else { try? FileManager.default.removeItem(at: destination) }
            throw error
        }
        if activeProfileID == id { await reloadClashWithCurrentProfile() }
    }

    /// Edit profile metadata (Name, URL)
    func editProfile(id: UUID, name: String, urlString: String) throws {
        guard !ClashViewModel.shared.isToggling else { throw URLError(.cancelled) }
        updateRevisions.invalidate(id)
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
        let revision = updateRevisions.begin(id)
        let validation = try await validateProfileContent(content)
        guard validation.valid else { throw URLError(.cannotParseResponse) }
        guard !ClashViewModel.shared.isToggling, updateRevisions.isCurrent(revision, for: id) else { throw CancellationError() }
        guard let index = profiles.firstIndex(where: { $0.id == id }),
              let path = profiles[index].path else {
            throw NSError(domain: "ProfileService", code: 11, userInfo: [NSLocalizedDescriptionKey: "Profile or path not found"])
        }

        // Write content to file
        try content.write(to: path, atomically: true, encoding: .utf8)
        profiles[index].needsRuleResources = validation.needsResources

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
        guard !ClashViewModel.shared.isToggling else {
            AppState.shared.reportError("Wait for the current core operation before deleting a profile.")
            return
        }
        updateRevisions.invalidate(id)
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }

        let profile = profiles[index]
        let wasActive = activeProfileID == id

        // Delete file if exists
        if let path = profile.path {
            try? FileManager.default.removeItem(at: path)
        }

        nodeSelections.remove(profile: id)
        if let data = try? JSONEncoder().encode(nodeSelections) {
            UserDefaults.standard.set(data, forKey: "profileNodeSelections")
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
        guard profiles.contains(where: { $0.id == id }) else { return }
        guard !isSwitchingProfile, !ClashViewModel.shared.isToggling, AppState.shared.operationStatus == nil else {
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

    /// Reload is serialized with all runtime changes. A saved profile never starts a stopped core.
    @MainActor
    @discardableResult
    func reloadClashWithCurrentProfile() async -> Bool {
        let vm = ClashViewModel.shared
        guard vm.isRunning else { return true }
        guard !vm.isToggling, AppState.shared.beginOperation("Applying Profile") else {
            AppState.shared.reportError("Profile saved; apply it after the current operation finishes.")
            return false
        }
        vm.isToggling = true
        defer {
            vm.isToggling = false
            if AppState.shared.operationStatus != nil { AppState.shared.finishOperation() }
        }
        let tunEnabled = AppState.shared.tunEnabled
        let proxyEnabled = AppState.shared.systemProxyEnabled
        do {
            try await ConfigService.shared.buildConfig(tunEnabled: tunEnabled)
            guard await vm.stopCore(intendedRestart: true) else {
                AppState.shared.finishOperation(error: "Profile saved; the old core could not stop.")
                return false
            }
            await vm.startCore(isRestart: true)
            guard vm.runtimeState.isAPIReady else {
                AppState.shared.finishOperation(error: "Profile saved but the core did not become ready.")
                return false
            }
            if proxyEnabled, !(await AppState.shared.enableSystemProxy()) { return false }
            try await ClashController.shared.fetchProxiesData()
            try await ClashController.shared.fetchRules()
            return true
        } catch {
            AppState.shared.finishOperation(error: "Profile saved but could not be applied: \(error.localizedDescription)")
            return false
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
        if let double = Double(cleaned), double.isFinite, double >= 0, double < Double(Int64.max) {
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
