import Foundation

extension ApplicationRouting {
    public struct LocalRoute: Equatable, Sendable {
        public let path: String
        public let target: String
        public let entries: Int
    }

    /// The first exact path rule wins. Keep duplicate information instead of
    /// presenting conflicting entries as a single unambiguous configuration.
    public static func localRoutes(in rules: String) -> [String: LocalRoute] {
        var result: [String: LocalRoute] = [:]
        for line in RuleDraftDocument(rules).rules {
            guard let form = line.rule.flatMap(RuleForm.init), form.type == "PROCESS-PATH", validPath(form.payload) else { continue }
            let previous = result[form.payload]
            result[form.payload] = LocalRoute(path: form.payload, target: previous?.target ?? form.target, entries: (previous?.entries ?? 0) + 1)
        }
        return result
    }

    public enum SelectionRoute: Hashable, Sendable {
        case inherited
        case target(String)
        case mixed
    }

    public static func selectionRoute(paths: [String], rules: String) -> SelectionRoute {
        let routes = localRoutes(in: rules)
        let values = Set(paths.map { routes[$0]?.target })
        guard values.count == 1 else { return paths.isEmpty ? .inherited : .mixed }
        guard let value = values.first, let target = value else { return .inherited }
        return .target(target)
    }

    public struct Observation: Sendable {
        public let path: String
        public let startedAt: Date
        public let rule: String
        public let payload: String
        public let chain: [String]

        public init(path: String, startedAt: Date, rule: String, payload: String, chain: [String]) {
            self.path = path; self.startedAt = startedAt; self.rule = rule; self.payload = payload; self.chain = chain
        }
    }

    public enum Verification: String, Sendable {
        case verified = "Verified"
        case pending = "Pending"
        case partial = "Partly verified"
        case different = "Different route"
        case inherited = "No override"
        case inactive = "Rule mode required"
        case unavailable = "Unavailable"
        case conflict = "Duplicate rules"
    }

    /// Only an exact core-reported rule match and a matching chain establish
    /// verification. Missing/blocked connections and OS app attribution are not proof.
    public static func verification(paths: [String], rules: String, observations: [Observation],
                                    available: Bool, ruleMode: Bool, notBefore: [String: Date] = [:]) -> Verification {
        let routes = localRoutes(in: rules)
        let configured = Set(paths).compactMap { routes[$0] }
        guard !configured.isEmpty else { return .inherited }
        if configured.contains(where: { $0.entries > 1 }) { return .conflict }
        guard ruleMode else { return .inactive }
        guard available else { return .unavailable }
        var verified = 0
        for route in configured {
            let current = observations.filter { $0.path == route.path && $0.startedAt >= (notBefore[route.path] ?? .distantPast) }
            guard !current.isEmpty else { continue }
            guard current.allSatisfy({
                $0.rule.replacingOccurrences(of: "-", with: "").lowercased() == "processpath" &&
                $0.payload == route.path && $0.chain.contains(route.target)
            }) else { return .different }
            verified += 1
        }
        if verified == configured.count && configured.count == Set(paths).count { return .verified }
        return verified > 0 ? .partial : .pending
    }
}
