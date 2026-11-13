import Foundation
import SubscriptionKit

@MainActor enum ActivityDiagnosticsService {
    enum Destination: Equatable, Identifiable {
        var id: String { String(describing: self) }
        case configuration, policies, nodes(String?), rules(String?), sources(String?), history
    }
    struct Row: Identifiable {
        let id: String
        let status: String
        let detail: String
        let attention: Bool
        var destination: Destination? = nil
    }
    struct Snapshot {
        let generation: UUID
        let revision: String
        let capturedAt: Date
        let rows: [Row]
        var audit: [ConfigurationAudit.Row] = []
        var differences: [ConfigurationDiff.Row] = []
    }
    static func load() async throws -> Snapshot {
        let vm = ClashViewModel.shared, controller = ClashController.shared, profiles = ProfileService.shared
        guard vm.runtimeState.isAPIReady, !vm.isToggling, !AppState.shared.isPerformingNetworkOperation else { throw CancellationError() }
        let generation = controller.runtimeGeneration, revision = profiles.activeProfileRevision, endpoint = controller.baseURL
        var rows: [Row] = []
        var savedDifferences: [ConfigurationDiff.Row] = []
        var audit: [ConfigurationAudit.Row] = []
        let checkpoint = try vm.recoveryCheckpoint()
        rows.append(Row(id: "Subscription", status: checkpoint.profileRevision == revision ? "Matches" : "Different",
            detail: checkpoint.profileRevision == revision ? "Running revision matches the selected subscription." : "The running core uses a different subscription revision.", attention: checkpoint.profileRevision != revision))
        do {
            let saved = try await ConfigService.shared.savedConfiguration(tunEnabled: checkpoint.tunEnabled)
            let differences = try ConfigurationDiff.compare(before: checkpoint.configuration, after: saved)
            savedDifferences = differences
            rows.append(Row(id: "Saved configuration", status: differences.isEmpty ? "Matches launch" : "Different",
                detail: differences.isEmpty ? "Saved file matches the verified runtime snapshot." : "\(differences.count) structural differences from the verified runtime snapshot; mode or log-level changes may be intentional.", attention: !differences.isEmpty, destination: .configuration))
        } catch { rows.append(Row(id: "Saved configuration", status: "Unavailable", detail: "The saved file could not be compared with the verified runtime snapshot.", attention: true, destination: .configuration)) }
        do {
            let data = try await controller.readRuntimeConfiguration()
            audit = try ConfigurationAudit.compare(configuration: checkpoint.configuration, response: data)
            for item in audit where item.status == .different {
                rows.append(Row(id: "Configuration · " + item.id, status: "Different", detail: "Verified launch: \(item.configured) · Running: \(item.running)", attention: true, destination: .configuration))
            }
            let unavailable = audit.filter { $0.status == .unavailable }.count
            rows.append(Row(id: "Runtime readback", status: "Read", detail: "\(audit.filter { $0.status == .match }.count) matching fields · \(unavailable) fields or sections not exposed by the API.", attention: false, destination: .configuration))
        } catch { rows.append(Row(id: "Runtime readback", status: "Unavailable", detail: "Runtime fields could not be read. Other diagnostic sections remain independent.", attention: true, destination: .configuration)) }
        do {
            try await controller.fetchProxiesData()
            let graph = PolicyGraph.inspect(groups: controller.proxyGroups, nodes: controller.proxyNodes)
            rows.append(Row(id: "Policy membership", status: graph.issues.isEmpty ? "No static issues" : "Check",
                detail: "\(controller.proxyGroups.count) groups · \(graph.edges.count) member references", attention: !graph.issues.isEmpty, destination: .policies))
            rows += graph.issues.enumerated().map { Row(id: "Policy issue \($0.offset + 1)", status: "Check", detail: $0.element, attention: true, destination: .policies) }
        } catch { rows.append(Row(id: "Policy membership", status: "Unavailable", detail: "The policy snapshot could not be read.", attention: true, destination: .policies)) }
        do {
            let resources = try await controller.fetchProxyResources()
            for resource in resources {
                let measured = resource.proxies.filter { $0.latest != nil }
                let failed = measured.filter { $0.latest?.delay == 0 }.count
                rows.append(Row(id: "Nodes · " + resource.name, status: failed > 0 ? "Check measurements" : "Read",
                    detail: "\(resource.proxies.count) nodes · \(measured.count) measured · \(failed) zero-delay results. Historical measurements, not a live connectivity test.", attention: failed > 0, destination: .nodes(resource.name)))
            }
        } catch { rows.append(Row(id: "Node resources", status: "Unavailable", detail: "Resource metadata could not be read.", attention: true, destination: .nodes(nil))) }
        let sources = try? RuleSourceDocument.read(configuration: checkpoint.configuration, subscription: nil, localRules: nil)
        do {
            let resources = try await controller.fetchRuleProviders()
            for resource in resources {
                let references = sources.map { String($0.references(to: resource.name).count) } ?? "Unknown"
                rows.append(Row(id: "Rules · " + resource.name, status: "Read", detail: "\(resource.ruleCount) rules · \(resource.behavior) · \(references) configured references. References include nested expressions and sub-rules; not runtime hit counts.", attention: false, destination: .rules(resource.name)))
            }
            if let sources {
                for name in Set(sources.rows.flatMap(\.providers)).subtracting(resources.map(\.name)).sorted() {
                    rows.append(Row(id: "Missing rule resource · " + name, status: "Unavailable", detail: "Referenced by the verified configuration but absent from this provider response.", attention: true, destination: .sources(name)))
                }
                for (index, issue) in sources.issues.enumerated() {
                    rows.append(Row(id: "Rule source issue \(index + 1)", status: "Check", detail: issue, attention: true, destination: .sources(nil)))
                }
            }
        } catch { rows.append(Row(id: "Rule resources", status: "Unavailable", detail: "Resource metadata could not be read.", attention: true, destination: .rules(nil))) }
        if sources == nil {
            rows.append(Row(id: "Rule sources", status: "Unavailable", detail: "References could not be read from the verified configuration.", attention: true, destination: .sources(nil)))
        }
        let operations = ResourceActivity.shared.current(generation: generation, endpoint: controller.baseURL)
        // One latest operation per resource; previous attempts remain available in session history.
        var seen = Set<String>()
        for entry in operations where seen.insert(entry.kind.rawValue + " · " + entry.name).inserted {
            rows.append(Row(id: "Last " + entry.kind.rawValue.lowercased() + " operation · " + entry.name,
                status: entry.outcome.rawValue, detail: entry.action.rawValue + " · " + entry.startedAt.formatted(date: .omitted, time: .standard) + " · " + entry.detail,
                attention: entry.outcome != .confirmed, destination: .history))
        }
        try Task.checkCancellation()
        guard generation == controller.runtimeGeneration, endpoint == controller.baseURL, revision == profiles.activeProfileRevision,
              vm.runtimeState.isAPIReady, !vm.isToggling, !AppState.shared.isPerformingNetworkOperation else { throw CancellationError() }
        return Snapshot(generation: generation, revision: revision, capturedAt: Date(), rows: rows, audit: audit, differences: savedDifferences)
    }
}
