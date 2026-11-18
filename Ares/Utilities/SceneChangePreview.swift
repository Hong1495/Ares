import Foundation
import SubscriptionKit

nonisolated enum SceneChangePreview {
    struct Row: Identifiable {
        let section: ScenarioSettings.Section
        let subject: String
        let before: String
        let after: String
        var id: [String] { [section.rawValue, subject] }
    }

    static func rows(from current: ScenarioSettings, to draft: ScenarioSettings) -> [Row] {
        let target = draft.resolved(from: current)
        var rows: [Row] = []
        func add(_ section: ScenarioSettings.Section, _ subject: String, _ before: String, _ after: String) {
            rows.append(.init(section: section, subject: subject, before: before, after: after))
        }
        if current.localRules != target.localRules {
            let before = current.localRules ?? "", after = target.localRules ?? ""
            let old = ApplicationRouting.localRoutes(in: before), new = ApplicationRouting.localRoutes(in: after)
            func label(_ rule: ApplicationRouting.LocalRoute?) -> String {
                guard let rule else { return "No local app rule" }
                return rule.entries == 1 ? rule.target : "\(rule.target) · \(rule.entries) exact rules"
            }
            for path in Set(old.keys).union(new.keys).sorted() where old[path] != new[path] {
                add(.rules, path, label(old[path]), label(new[path]))
            }
            let oldRules = RuleDraftDocument(before).rules.compactMap(\.rule)
            let newRules = RuleDraftDocument(after).rules.compactMap(\.rule)
            let oldOther = oldRules.filter { !isExactAppRule($0, known: old) }
            let newOther = newRules.filter { !isExactAppRule($0, known: new) }
            if oldOther != newOther {
                func counts(_ lines: [String]) -> [String: Int] { Dictionary(lines.map { ($0, 1) }, uniquingKeysWith: +) }
                let oldCounts = counts(oldOther), newCounts = counts(newOther)
                let removed = oldCounts.reduce(0) { $0 + max(0, $1.value - newCounts[$1.key, default: 0]) }
                let added = newCounts.reduce(0) { $0 + max(0, $1.value - oldCounts[$1.key, default: 0]) }
                let summary = added + removed == 0 ? "Order changes" : "\(added) added · \(removed) removed"
                add(.rules, "Other local rules", "\(oldOther.count) rules", "\(newOther.count) rules · \(summary)")
            }
            if oldRules != newRules, old == new, oldOther == newOther {
                add(.rules, "Rule order or expressions", "Current rules", "Change saved order or expressions")
            }
            if oldRules == newRules { add(.rules, "Saved rule text", current.localRules == nil ? "Inherited" : "Local copy", target.localRules == nil ? "Remove local copy" : "Save local copy") }
        }
        if current.policy != target.policy {
            let old = try? PolicyConfiguration.decodeOverrides(current.policy ?? "{}")
            let new = try? PolicyConfiguration.decodeOverrides(target.policy ?? "{}")
            if let old, let new, old != new {
                for group in Set(old.keys).union(new.keys).sorted() where old[group] != new[group] {
                    let before = old[group], after = new[group]
                    let status = before?["_create"] == "true" ? "Local group" : before?["_delete"] == "true" ? "Removed by override" : before == nil ? "Inherited or absent" : "Local override"
                    let change = after?["_delete"] == "true" ? "Remove group" : after == nil
                        ? (before?["_create"] == "true" ? "Remove local group definition" : "Restore inheritance")
                        : after?["_create"] == "true" && before?["_create"] != "true" ? "Add local group" : "Change group definition"
                    add(.policy, group, status, change)
                }
            } else { add(.policy, "Policy overrides", "Current overrides", target.policy == nil ? "Clear overrides" : "Use scene overrides") }
        }
        if current.dns != target.dns {
            let old = try? DNSConfiguration.decode(current.dns ?? "{}")
            let new = try? DNSConfiguration.decode(target.dns ?? "{}")
            if let old, let new, old != new {
                for key in Set(old.keys).union(new.keys).sorted() where old[key] != new[key] {
                    add(.dns, key, old[key] == nil ? "Inherited" : "Local override", new[key] == nil ? "Restore inheritance" : "Use scene override")
                }
            } else { add(.dns, "DNS overrides", "Current overrides", target.dns == nil ? "Clear overrides" : "Use scene overrides") }
        }
        if current.egress != target.egress {
            let old = try? EgressConfiguration.decode(current.egress ?? EgressConfiguration.empty)
            let new = try? EgressConfiguration.decode(target.egress ?? EgressConfiguration.empty)
            if let old, let new, old != new {
                for node in Set(old.nodes.keys).union(new.nodes.keys).sorted() where old.nodes[node] != new.nodes[node] {
                    add(.egress, "Node: " + node, old.nodes[node] == nil ? "Inherited" : "Local override", new.nodes[node] == nil ? "Restore inheritance" : "Use scene override")
                }
                for (name, before, after) in [("Interface", old.interface, new.interface), ("Listeners", old.listeners, new.listeners), ("Tunnels", old.tunnels, new.tunnels)] where before != after {
                    add(.egress, name, before == nil ? "Inherited" : "Local override", after == nil ? "Restore inheritance" : "Use scene override")
                }
            } else { add(.egress, "Routing overrides", "Current overrides", target.egress == nil ? "Clear overrides" : "Use scene overrides") }
        }
        if current.mode != target.mode, let mode = target.mode { add(.mode, "Proxy Mode", current.mode?.capitalized ?? "Current", mode.capitalized) }
        let oldNodes = current.selections ?? [:], newNodes = target.selections ?? [:]
        for name in Set(oldNodes.keys).union(newNodes.keys).sorted() where oldNodes[name] != newNodes[name] {
            add(.selections, name, oldNodes[name] ?? "No saved choice", newNodes[name] ?? "Clear saved choice")
        }
        return rows
    }

    static func appName(_ path: String) -> String {
        path.split(separator: "/").first { $0.lowercased().hasSuffix(".app") }.map { String($0.dropLast(4)) }
            ?? (path as NSString).lastPathComponent
    }

    private static func isExactAppRule(_ line: String, known: [String: ApplicationRouting.LocalRoute]) -> Bool {
        guard let form = RuleForm(line), form.type == "PROCESS-PATH" else { return false }
        return known[form.payload]?.entries == 1
    }
}
