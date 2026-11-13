import Foundation

/// A snapshot of explicit overrides, never a frozen subscription or a claim about runtime health.
nonisolated struct ScenarioSettings: Codable, Equatable, Sendable {
    let localRules: String?
    let dns: String?
    let policy: String?
    let egress: String?

    static func capture(profile: UUID, defaults: UserDefaults) -> Self {
        Self(localRules: defaults.string(forKey: "localRules"),
             dns: defaults.string(forKey: "dnsOverrides." + profile.uuidString),
             policy: defaults.string(forKey: "policyGroupOverrides." + profile.uuidString),
             egress: defaults.string(forKey: "egressOverrides." + profile.uuidString))
    }
    func install(profile: UUID, defaults: UserDefaults) {
        let values: [(String, String?)] = [("localRules", localRules), ("dnsOverrides." + profile.uuidString, dns),
            ("policyGroupOverrides." + profile.uuidString, policy), ("egressOverrides." + profile.uuidString, egress)]
        for (key, value) in values {
            if let value { defaults.set(value, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
    }
    struct Difference: Identifiable, Sendable {
        let id: String
        let before: String
        let after: String
    }
    func differences(from previous: Self) -> [Difference] {
        zip(["Local Rules", "DNS", "Policy Groups", "Routing & Listeners"],
            zip([previous.localRules, previous.dns, previous.policy, previous.egress], [localRules, dns, policy, egress]))
        .compactMap { label, pair in
            guard pair.0 != pair.1 else { return nil }
            return Difference(id: label, before: pair.0 == nil ? "Inherited / unset" : "Saved override",
                              after: pair.1 == nil ? "Restore inheritance" : "Replace saved override")
        }
    }
}

nonisolated struct ManualScenario: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    let profileID: UUID
    let sourceRevision: String
    let createdAt: Date
    let settings: ScenarioSettings
    init(name: String, profileID: UUID, sourceRevision: String, settings: ScenarioSettings) throws {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 80, !clean.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw ScenarioLibrary.Failure.invalidName }
        self.id = UUID(); self.name = clean; self.profileID = profileID; self.sourceRevision = sourceRevision
        self.createdAt = Date(); self.settings = settings
    }
}

/// Private atomic storage; override documents can contain listener credentials.
nonisolated enum ScenarioLibrary {
    enum Failure: LocalizedError {
        case invalidName, incompatible, duplicate, invalid
        var errorDescription: String? {
            switch self {
            case .invalidName: return "Enter a name of 1–80 characters without control characters."
            case .incompatible: return "This scenario library has an unsupported version."
            case .duplicate: return "A scenario with that name already exists for this subscription."
            case .invalid: return "The scenario library could not be read. Existing data was retained."
            }
        }
    }
    private struct Document: Codable { let schema: Int; let scenarios: [ManualScenario] }
    static func load(directory: URL) throws -> [ManualScenario] {
        let file = directory.appendingPathComponent("scenarios.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        do {
            let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: file))
            guard document.schema == 1 else { throw Failure.incompatible }
            try validate(document.scenarios)
            return document.scenarios
        } catch let error as Failure { throw error }
        catch { throw Failure.invalid }
    }
    static func save(_ scenarios: [ManualScenario], directory: URL) throws {
        try validate(scenarios)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let file = directory.appendingPathComponent("scenarios.json")
        try JSONEncoder().encode(Document(schema: 1, scenarios: scenarios)).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
    private static func validate(_ scenarios: [ManualScenario]) throws {
        guard Set(scenarios.map(\.id)).count == scenarios.count else { throw Failure.invalid }
        var names = Set<String>()
        for item in scenarios {
            _ = try ManualScenario(name: item.name, profileID: item.profileID, sourceRevision: item.sourceRevision, settings: item.settings)
            let key = item.profileID.uuidString + ":" + item.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard names.insert(key).inserted else { throw Failure.duplicate }
        }
    }
}
