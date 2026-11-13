import Foundation

/// Lossless local-rule draft. Unknown syntax, comments and blank lines survive form edits.
public struct RuleDraftDocument {
    public struct Line: Identifiable, Equatable {
        public let id: UUID
        public var text: String
        public init(_ text: String) { id = UUID(); self.text = text }
        public var rule: String? {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }
            return trimmed.hasPrefix("- ") ? String(trimmed.dropFirst(2)) : trimmed
        }
    }
    public var lines: [Line]
    public init(_ text: String) { lines = text.components(separatedBy: "\n").map(Line.init) }
    public var text: String { lines.map(\.text).joined(separator: "\n") }
    public var rules: [Line] { lines.filter { $0.rule != nil } }
    public mutating func replace(id: UUID, with rule: String) {
        guard let index = lines.firstIndex(where: { $0.id == id }) else { return }
        let old = lines[index].text
        let indentation = String(old.prefix(while: { $0 == " " || $0 == "\t" }))
        let marker = old.trimmingCharacters(in: .whitespaces).hasPrefix("- ") ? "- " : ""
        lines[index].text = indentation + marker + rule
    }
    public mutating func remove(id: UUID) { lines.removeAll { $0.id == id } }
    public mutating func move(id: UUID, by offset: Int) {
        let active = rules
        guard let from = active.firstIndex(where: { $0.id == id }), active.indices.contains(from + offset),
              let a = lines.firstIndex(where: { $0.id == id }),
              let b = lines.firstIndex(where: { $0.id == active[from + offset].id }) else { return }
        lines.swapAt(a, b)
    }
    public mutating func append(_ rule: String) {
        if lines.last?.text == "" { lines.insert(Line(rule), at: lines.count - 1) }
        else { lines.append(Line(rule)) }
    }
}

/// Conservative form projection. Unsupported/ambiguous expressions remain editable as raw text.
public struct RuleForm: Equatable {
    public static let types = ["DOMAIN", "DOMAIN-SUFFIX", "DOMAIN-KEYWORD", "IP-CIDR", "IP-CIDR6",
                               "SRC-IP-CIDR", "GEOIP", "GEOSITE", "RULE-SET", "PROCESS-NAME",
                               "PROCESS-PATH", "DST-PORT", "SRC-PORT", "NETWORK", "MATCH"]
    public var type: String
    public var payload: String
    public var target: String
    public var noResolve: Bool
    public init(type: String = "DOMAIN-SUFFIX", payload: String = "", target: String = "DIRECT", noResolve: Bool = false) {
        self.type = type; self.payload = payload; self.target = target; self.noResolve = noResolve
    }
    public init?(_ raw: String) {
        let parts = raw.components(separatedBy: ",")
        guard let type = parts.first, Self.types.contains(type) else { return nil }
        let baseCount = type == "MATCH" ? 2 : 3
        guard parts.count == baseCount || parts.count == baseCount + 1 else { return nil }
        let extra = parts.count > baseCount
        self.init(type: type, payload: type == "MATCH" ? "" : parts[1], target: parts[baseCount - 1], noResolve: extra)
        guard (!extra || (parts.last == "no-resolve" && allowsNoResolve)), validationError == nil,
              serialized == raw else { return nil }
    }
    public var allowsNoResolve: Bool { ["IP-CIDR", "IP-CIDR6", "GEOIP", "RULE-SET"].contains(type) }
    public var validationError: String? {
        guard Self.types.contains(type) else { return "Use the source editor for this rule type." }
        guard !target.trimmingCharacters(in: .whitespaces).isEmpty else { return "Choose a target policy." }
        guard type == "MATCH" || !payload.trimmingCharacters(in: .whitespaces).isEmpty else { return "Enter a rule value." }
        guard ![target, payload].contains(where: { $0.contains(",") || $0.contains("\n") || $0.contains("\r") }) else {
            return "Use the source editor for values containing commas or newlines."
        }
        if type == "NETWORK", !["tcp", "udp"].contains(payload.lowercased()) { return "Network must be tcp or udp." }
        return nil
    }
    public var serialized: String {
        (type == "MATCH" ? [type, target] : [type, payload, target]).joined(separator: ",")
            + (noResolve && allowsNoResolve ? ",no-resolve" : "")
    }
}
