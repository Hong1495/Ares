import Foundation

/// Additive recommendations: never replace subscription groups or routing rules.
public enum RecommendedPolicies {
    public struct Plan: Sendable {
        public let overrides: String
        public let automatic: String
        public let fallback: String
        public let manual: String
    }
    public static func make(source: String, overrides: String) throws -> Plan {
        let effective = try PolicyConfiguration.apply(source: source, overrides: overrides)
        let catalog = try PolicyConfiguration.catalog(effective)
        guard !catalog.nodes.isEmpty || !catalog.providers.isEmpty else {
            throw PolicyConfiguration.Failure.invalid("This subscription has no nodes or node resources.")
        }
        var edits = try PolicyConfiguration.decodeOverrides(overrides)
        var occupied = Set(try PolicyConfiguration.read(effective).map(\.name) + catalog.nodes + Array(edits.keys))
        func unique(_ base: String) -> String {
            var name = base; var suffix = 2
            while occupied.contains(name) { name = base + " \(suffix)"; suffix += 1 }
            occupied.insert(name); return name
        }
        let automatic = unique("Ares Auto"), fallback = unique("Ares Fallback"), manual = unique("Ares Route")
        let members = try PolicyConfiguration.list(catalog.nodes)
        let resources = try PolicyConfiguration.list(catalog.providers)
        for (name, type) in [(automatic, "url-test"), (fallback, "fallback")] {
            var fields = ["_create": "true", "type": type, "proxies": members, "use": resources,
                          "url": "https://www.gstatic.com/generate_204", "interval": "300", "timeout": "5000", "lazy": "false"]
            if type == "url-test" { fields["tolerance"] = "50" }
            edits[name] = fields
        }
        edits[manual] = ["_create": "true", "type": "select", "proxies": try PolicyConfiguration.list([automatic, fallback] + catalog.nodes), "use": resources]
        let result = try PolicyConfiguration.encodeOverrides(edits)
        _ = try PolicyConfiguration.apply(source: source, overrides: result)
        return Plan(overrides: result, automatic: automatic, fallback: fallback, manual: manual)
    }
}
