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
        
        // Load profiles
        loadProfiles()
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
        
        // Auto-select if first profile
        if profiles.count == 1 {
            activeProfileID = profile.id
        }
        
        saveProfiles()
        print("[ProfileService] Added remote profile: \(name)")
    }
    
    /// Add a local profile
    func addLocalProfile(name: String, fileURL: URL) throws {
        // Copy file to profiles directory
        let filename = "\(UUID().uuidString).yaml"
        let destination = profilesDir.appendingPathComponent(filename)
        try FileManager.default.copyItem(at: fileURL, to: destination)
        
        let profile = Profile.local(name: name, path: destination)
        profiles.append(profile)
        
        // Auto-select if first profile
        if profiles.count == 1 {
            activeProfileID = profile.id
        }
        
        saveProfiles()
        print("[ProfileService] Added local profile: \(name)")
    }
    
    /// Update a remote profile by downloading latest content
    func updateProfile(_ profile: inout Profile) async throws {
        guard profile.type == .remote, let url = profile.url else {
            throw NSError(domain: "ProfileService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not a remote profile"])
        }
        
        print("[ProfileService] Downloading profile from: \(url)")
        
        // Download profile
        let (data, _) = try await URLSession.shared.data(from: url)
        
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
        
        // Download updated content
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let content = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "ProfileService", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid profile content"])
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
    
    /// Set active profile
    func setActiveProfile(id: UUID) {
        activeProfileID = id
        saveProfiles()
    }
}
