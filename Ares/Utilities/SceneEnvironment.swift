import Foundation

extension Notification.Name {
    static let sceneManuallyApplied = Notification.Name("Ares.sceneManuallyApplied")
}

/// Only system-observed path properties. Interface type is not a trusted network identity.
nonisolated struct SceneEnvironment: Equatable, Sendable {
    var available: Bool
    var kind: String
    var interface: String
    var expensive: Bool
    var constrained: Bool
    static let unknown = Self(available: false, kind: "unknown", interface: "", expensive: false, constrained: false)
}
nonisolated struct SceneTrigger: Codable, Equatable, Sendable {
    var enabled = false
    var kind = "any"
    var interface = ""
    var cost = "any"
    var constrained = "any"
    var priority = 0
    func validate() throws {
        guard ["any", "wifi", "wired", "cellular"].contains(kind), ["any", "yes", "no"].contains(cost),
              ["any", "yes", "no"].contains(constrained), (-100...100).contains(priority),
              interface.utf8.count < 16,
              interface.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-").contains($0) }),
              !enabled || kind != "any" || !interface.isEmpty || cost != "any" || constrained != "any" else {
            throw ScenarioLibrary.Failure.invalid
        }
    }
    func reason(environment: SceneEnvironment) -> String? {
        if !enabled { return "Trigger disabled" }
        if !environment.available { return "No available network path" }
        if kind != "any" && kind != environment.kind { return "Network type differs" }
        if !interface.isEmpty && interface != environment.interface { return "Interface differs or is unknown" }
        if cost != "any" && (cost == "yes") != environment.expensive { return "Metered condition differs" }
        if constrained != "any" && (constrained == "yes") != environment.constrained { return "Low Data Mode differs" }
        return nil
    }
}
nonisolated enum SceneMatcher {
    struct Row: Identifiable { let id: UUID; let name: String; let priority: Int; let reason: String; let matches: Bool }
    struct Result {
        let rows: [Row]
        let winner: UUID?
        let conflict: Bool
    }
    static func evaluate(_ scenes: [ManualScenario], profile: UUID?, environment: SceneEnvironment) -> Result {
        let rows = scenes.filter { $0.profileID == profile }.map { scene -> Row in
            let trigger = scene.trigger ?? SceneTrigger()
            let valid = (try? trigger.validate()) != nil
            let reason = valid ? trigger.reason(environment: environment) : "Invalid trigger"
            return Row(id: scene.id, name: scene.name, priority: trigger.priority,
                       reason: reason ?? "All conditions match", matches: valid && reason == nil)
        }
        let candidates = rows.filter(\.matches)
        let highest = candidates.map(\.priority).max()
        let winners = candidates.filter { $0.priority == highest }
        return Result(rows: rows, winner: winners.count == 1 ? winners[0].id : nil, conflict: winners.count > 1)
    }
}

/// Stable candidate + environment + settings fingerprint. No timers, storage or side effects here.
nonisolated struct SceneDebounce {
    private var key: String?
    private var since: TimeInterval = 0
    private var lastAttempt: TimeInterval?
    mutating func reset() { key = nil }
    mutating func ready(key next: String?, now: TimeInterval, stableFor: TimeInterval = 10, cooldown: TimeInterval = 30) -> Bool {
        guard let next else { reset(); return false }
        if key != next { key = next; since = now; return false }
        return now - since >= stableFor && lastAttempt.map { now - $0 >= cooldown } != false
    }
    mutating func attempted(now: TimeInterval) { lastAttempt = now; reset() }
}
