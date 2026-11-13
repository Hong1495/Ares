import Foundation
import Yams

/// Exact executable rules only. Display grouping (app bundles, helpers, remote clients) is not an identity match.
public enum ApplicationRouting {
    public static func validPath(_ path: String) -> Bool {
        path.hasPrefix("/") && !path.hasSuffix(".app") && !path.contains(where: { $0 == "," || $0.isNewline || $0.asciiValue.map { $0 < 32 } == true })
    }
    public static func paths(in rules: String) -> [String] {
        Array(Set(RuleDraftDocument(rules).rules.compactMap { line in
            guard let form = line.rule.flatMap(RuleForm.init), form.type == "PROCESS-PATH", validPath(form.payload) else { return nil }
            return form.payload
        })).sorted()
    }
    public static func replacing(_ rules: String, paths: [String], target: String?) throws -> String {
        guard !paths.isEmpty, paths.allSatisfy(validPath) else { throw PolicyConfiguration.Failure.invalid("Choose a verified executable path. Unknown processes cannot be routed by application.") }
        let paths = Set(paths)
        var document = RuleDraftDocument(rules)
        document.lines.removeAll { line in
            guard let form = line.rule.flatMap(RuleForm.init) else { return false }
            return form.type == "PROCESS-PATH" && paths.contains(form.payload)
        }
        guard let target else { return document.text }
        let forms = paths.sorted().map { RuleForm(type: "PROCESS-PATH", payload: $0, target: target) }
        guard forms.allSatisfy({ $0.validationError == nil }) else { throw PolicyConfiguration.Failure.invalid("Choose a valid routing target.") }
        return forms.map(\.serialized).joined(separator: "\n") + (document.text.isEmpty ? "" : "\n" + document.text)
    }
    public struct Match: Identifiable, Sendable {
        public var id: Int { order }
        public let order: Int
        public let expression: String
        public let explanation: String
    }
    /// Candidate/conflict evidence, not a simulation of mihomo's full rule engine.
    public static func evidence(paths: [String], rules: [String]) -> [Match] {
        let names = Set(paths.map { ($0 as NSString).lastPathComponent })
        return rules.enumerated().compactMap { index, raw in
            if let form = RuleForm(raw) {
                if form.type == "PROCESS-PATH", paths.contains(form.payload) { return Match(order: index + 1, expression: raw, explanation: "Exact executable match") }
                if form.type == "PROCESS-NAME", names.contains(form.payload) { return Match(order: index + 1, expression: raw, explanation: "Process name match; may include other executables") }
                if form.type == "MATCH" { return Match(order: index + 1, expression: raw, explanation: "Catch-all") }
            }
            if raw.hasPrefix("AND,") || raw.hasPrefix("OR,") || raw.hasPrefix("NOT,") || raw.hasPrefix("RULE-SET,") || raw.hasPrefix("PROCESS-PATH-REGEX,") || raw.hasPrefix("PROCESS-NAME-REGEX,") {
                return Match(order: index + 1, expression: raw, explanation: "Advanced rule · evaluated by the core")
            }
            return nil
        }
    }
    public static func configuredRules(_ source: String) throws -> [String] {
        let validated = try EffectiveConfiguration.build(source: source, defaults: "{}", overrides: [])
        return try Yams.compose(yaml: validated)?["rules"]?.sequence?.compactMap(\.string) ?? []
    }
}
