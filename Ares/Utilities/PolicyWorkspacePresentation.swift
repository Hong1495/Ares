import Foundation
import SubscriptionKit

nonisolated enum PolicyWorkspacePresentation {
    enum Verification: String {
        case confirmed = "Read back", different = "Different", unavailable = "Unavailable"
    }
    static func source(name: String, overrides: String) -> String {
        guard let edits = try? PolicyConfiguration.decodeOverrides(overrides) else { return "Unknown" }
        if edits[name]?["_create"] == "true" { return "Local group" }
        return edits[name] == nil ? "Subscription" : "Local override"
    }
    static func verification(_ group: PolicyConfiguration.Group, live: [ProxyGroup]?) -> Verification {
        guard let live else { return .unavailable }
        let types = ["select": "Selector", "url-test": "URLTest", "fallback": "Fallback", "load-balance": "LoadBalance"]
        guard let actual = live.first(where: { $0.name == group.name }), actual.type == types[group.type] else { return .different }
        if ["filter", "exclude-filter", "exclude-type"].allSatisfy({ group.fields[$0, default: ""].isEmpty }) {
            var position = actual.all.startIndex
            for member in group.members {
                guard let index = actual.all[position...].firstIndex(of: member) else { return .different }
                position = actual.all.index(after: index)
            }
        }
        return .confirmed
    }
    static func current(_ group: PolicyConfiguration.Group, live: [ProxyGroup]?) -> String {
        guard let actual = live?.first(where: { $0.name == group.name }) else { return "—" }
        return actual.type == "LoadBalance" ? "Per connection" : actual.now ?? "—"
    }
}
