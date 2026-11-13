import Foundation
import Yams

/// Read-only comparison against mihomo v1.19.34's GET /configs contract.
/// Only allowlisted non-secret fields leave the parser. This is not a full runtime dump.
public enum ConfigurationAudit {
    public enum Status: String, Sendable { case match = "Matches", different = "Different", unavailable = "Not exposed", inactive = "TUN inactive", unspecified = "Core default" }
    public struct Row: Sendable, Identifiable {
        public let id: String
        public let configured: String
        public let running: String
        public let status: Status
    }
    public enum AuditError: LocalizedError {
        case invalidConfiguration, invalidResponse
        public var errorDescription: String? {
            switch self {
            case .invalidConfiguration: return "The saved configuration could not be inspected."
            case .invalidResponse: return "The core returned an invalid configuration response."
            }
        }
    }

    // Paths differ when the API flattens or renames a setting.
    private static let fields: [(String, String)] = [
        ("port", "port"), ("socks-port", "socks-port"), ("mixed-port", "mixed-port"),
        ("mode", "mode"), ("log-level", "log-level"), ("allow-lan", "allow-lan"),
        ("interface-name", "interface-name"), ("ipv6", "ipv6"), ("find-process-mode", "find-process-mode"),
        ("tcp-concurrent", "tcp-concurrent"), ("unified-delay", "unified-delay"),
        ("keep-alive-interval", "keep-alive-interval"), ("keep-alive-idle", "keep-alive-idle"),
        ("disable-keep-alive", "disable-keep-alive"), ("sniffer.enable", "sniffing"),
        ("tun.enable", "tun.enable"), ("tun.stack", "tun.stack"), ("tun.mtu", "tun.mtu"),
        ("tun.device", "tun.device"), ("tun.auto-route", "tun.auto-route"),
        ("tun.auto-detect-interface", "tun.auto-detect-interface")
    ]

    public static func compare(configuration: String, response: Data) throws -> [Row] {
        let expected: Node
        do {
            // Use the existing validation/alias expansion path, without adding defaults.
            let resolved = try EffectiveConfiguration.build(source: configuration, defaults: "{}", overrides: [])
            guard let parsed = try Yams.compose(yaml: resolved) else { throw AuditError.invalidConfiguration }
            expected = parsed
        } catch { throw AuditError.invalidConfiguration }
        let actual: Node
        do {
            guard let object = try JSONSerialization.jsonObject(with: response) as? [String: Any],
                  object["mode"] is String, object["tun"] is [String: Any],
                  let json = String(data: response, encoding: .utf8),
                  let parsed = try Yams.compose(yaml: json) else { throw AuditError.invalidResponse }
            actual = parsed
        } catch { throw AuditError.invalidResponse }
        guard let tunEnable = value(actual, "tun.enable"), tunEnable.tag == Tag(.bool), let tunActive = tunEnable.bool else {
            throw AuditError.invalidResponse
        }
        var rows = fields.map { path, api -> Row in
            let wanted = value(expected, path)
            let running = value(actual, api)
            let status: Status
            if path.hasPrefix("tun."), path != "tun.enable", !tunActive { status = .inactive }
            else if wanted == nil { status = .unspecified }
            else if running == nil { status = .unavailable }
            else { status = equivalent(wanted!, running!, path: path) ? .match : .different }
            return Row(id: path, configured: display(wanted), running: display(running), status: status)
        }
        // Deliberately no values for these sections: they may contain tokens or credentials.
        for key in ["dns", "udp-timeout", "profile", "proxies", "proxy-groups", "proxy-providers", "rules", "rule-providers", "listeners", "tunnels"] where expected[key] != nil {
            rows.append(Row(id: key, configured: "Configured", running: "—", status: .unavailable))
        }
        return rows
    }

    /// Runtime mode/log-level can be PATCHed after startup. Record those verified values
    /// in a recovery copy without rewriting the user's subscription or saved config file.
    public static func recoveryConfiguration(configuration: String, response: Data) throws -> String {
        do {
            let normalized = try EffectiveConfiguration.build(source: configuration, defaults: "{}", overrides: [])
            guard var node = try Yams.compose(yaml: normalized),
                  let json = String(data: response, encoding: .utf8), let actual = try Yams.compose(yaml: json),
                  let mode = actual["mode"], let log = actual["log-level"],
                  ["rule", "global", "direct"].contains(mode.string ?? ""),
                  ["silent", "error", "warning", "info", "debug"].contains(log.string ?? "") else {
                throw AuditError.invalidResponse
            }
            node["mode"] = mode
            node["log-level"] = log
            let result = try Yams.serialize(node: node, allowUnicode: true)
            try verifyStartup(configuration: result, response: response)
            return result
        } catch { throw AuditError.invalidResponse }
    }

    /// Required readiness contract. Other normalized/optional fields remain diagnostic only.
    public static func verifyStartup(configuration: String, response: Data) throws {
        let required: Set<String> = ["port", "socks-port", "mixed-port", "mode", "log-level", "allow-lan", "ipv6", "find-process-mode", "tun.enable"]
        let rows = try compare(configuration: configuration, response: response)
        guard rows.filter({ required.contains($0.id) || ($0.id == "interface-name" && $0.status != .unspecified) }).allSatisfy({ $0.status == .match }) else {
            throw AuditError.invalidResponse
        }
    }

    private static func value(_ node: Node, _ path: String) -> Node? {
        path.split(separator: ".").reduce(Optional(node)) { $0?[String($1)] }
    }
    private static func display(_ node: Node?) -> String {
        guard let node else { return "—" }
        guard let scalar = node.scalar else { return "Unsupported value" }
        return scalar.string.isEmpty ? "Auto / empty" : scalar.string
    }
    private static func equivalent(_ lhs: Node, _ rhs: Node, path: String) -> Bool {
        // TUN stack's JSON encoder uses title case while config accepts lower case.
        if path == "tun.stack" { return lhs.string?.lowercased() == rhs.string?.lowercased() }
        return lhs == rhs
    }
}
