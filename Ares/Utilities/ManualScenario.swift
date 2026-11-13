import Foundation

/// A snapshot of explicit overrides, never a frozen subscription or a claim about runtime health.
nonisolated struct ScenarioSettings: Codable, Equatable, Sendable {
    var localRules: String?
    var dns: String?
    var policy: String?
    var egress: String?
    var mode: String? = nil
    var selections: [String: String]? = nil

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
        var rows: [Difference] = zip(["Local Rules", "DNS", "Policy Groups", "Routing & Listeners"],
            zip([previous.localRules, previous.dns, previous.policy, previous.egress], [localRules, dns, policy, egress]))
        .compactMap { label, pair in
            guard pair.0 != pair.1 else { return nil }
            return Difference(id: label, before: pair.0 == nil ? "Inherited / unset" : "Saved override",
                              after: pair.1 == nil ? "Restore inheritance" : "Replace saved override")
        }
        if let mode, mode != previous.mode {
            rows.append(Difference(id: "Proxy Mode", before: previous.mode ?? "Current", after: mode.capitalized))
        }
        if let selections, selections != previous.selections {
            rows.append(Difference(id: "Node Selections", before: "Current saved selections", after: "Replace with \(selections.count) saved choices"))
        }
        return rows
    }

    func resolvingRouting(from current: Self) -> Self {
        var result = self
        result.mode = mode ?? current.mode
        result.selections = selections ?? current.selections
        return result
    }
}

nonisolated struct ManualScenario: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    let profileID: UUID
    var sourceRevision: String
    let createdAt: Date
    var settings: ScenarioSettings
    var updatedAt: Date?
    var trigger: SceneTrigger? = nil
    var validatedRevision: String? = nil
    init(name: String, profileID: UUID, sourceRevision: String, settings: ScenarioSettings) throws {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 80, !clean.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw ScenarioLibrary.Failure.invalidName }
        self.id = UUID(); self.name = clean; self.profileID = profileID; self.sourceRevision = sourceRevision
        self.createdAt = Date(); self.settings = settings
    }

    func edited(name: String, settings: ScenarioSettings) throws -> Self {
        let validated = try Self(name: name, profileID: profileID, sourceRevision: sourceRevision, settings: settings)
        var result = self
        result.name = validated.name
        result.settings = settings
        result.updatedAt = Date()
        return result
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
    static func replace(_ original: ManualScenario, with edited: ManualScenario, directory: URL) throws {
        var library = try load(directory: directory)
        guard let index = library.firstIndex(of: original), original.id == edited.id,
              original.profileID == edited.profileID, original.sourceRevision == edited.sourceRevision,
              original.createdAt == edited.createdAt else { throw Failure.invalid }
        library[index] = edited
        try save(library, directory: directory)
    }
    private static func validate(_ scenarios: [ManualScenario]) throws {
        guard Set(scenarios.map(\.id)).count == scenarios.count else { throw Failure.invalid }
        var names = Set<String>()
        for item in scenarios {
            try item.trigger?.validate()
            _ = try ManualScenario(name: item.name, profileID: item.profileID, sourceRevision: item.sourceRevision, settings: item.settings)
            let key = item.profileID.uuidString + ":" + item.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard names.insert(key).inserted else { throw Failure.duplicate }
        }
    }
}
