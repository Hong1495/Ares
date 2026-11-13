import Foundation
import SubscriptionKit

@MainActor enum ActivityDiagnosticsService {
    struct Row: Identifiable {
        let id: String
        let status: String
        let detail: String
        let attention: Bool
    }
    struct Snapshot {
        let generation: UUID
        let revision: String
        let capturedAt: Date
        let rows: [Row]
    }
    static func load() async throws -> Snapshot {
        let vm = ClashViewModel.shared, controller = ClashController.shared, profiles = ProfileService.shared
        guard vm.runtimeState.isAPIReady, !vm.isToggling, !AppState.shared.isPerformingNetworkOperation else { throw CancellationError() }
        let generation = controller.runtimeGeneration, revision = profiles.activeProfileRevision
        var rows: [Row] = []
        let checkpoint = try await vm.captureRecoveryCheckpoint()
        rows.append(Row(id: "Subscription", status: checkpoint.profileRevision == revision ? "Matches" : "Different",
            detail: checkpoint.profileRevision == revision ? "Running revision matches the selected subscription." : "The running core uses a different subscription revision.", attention: checkpoint.profileRevision != revision))
        do {
            let saved = try await ConfigService.shared.savedConfiguration(tunEnabled: checkpoint.tunEnabled)
            let differences = try ConfigurationDiff.compare(before: checkpoint.configuration, after: saved)
            rows.append(Row(id: "Saved configuration", status: differences.isEmpty ? "Matches launch" : "Different",
                detail: differences.isEmpty ? "Saved file matches the verified runtime snapshot." : "\(differences.count) structural differences from the verified runtime snapshot; mode or log-level changes may be intentional.", attention: !differences.isEmpty))
        } catch { rows.append(Row(id: "Saved configuration", status: "Unavailable", detail: "The saved file could not be compared with the verified runtime snapshot.", attention: true)) }
        let data = try await controller.readRuntimeConfiguration()
        let audit = try ConfigurationAudit.compare(configuration: checkpoint.configuration, response: data)
        for item in audit where item.status == .different {
            rows.append(Row(id: "Configuration · " + item.id, status: "Different", detail: "Verified launch: \(item.configured) · Running: \(item.running)", attention: true))
        }
        let unavailable = audit.filter { $0.status == .unavailable }.count
        rows.append(Row(id: "Runtime readback", status: "Read", detail: "\(audit.filter { $0.status == .match }.count) matching fields · \(unavailable) fields or sections not exposed by the API.", attention: false))
        do {
            try await controller.fetchProxiesData()
            let graph = PolicyGraph.inspect(groups: controller.proxyGroups, nodes: controller.proxyNodes)
            rows.append(Row(id: "Policy membership", status: graph.issues.isEmpty ? "No static issues" : "Check",
                detail: "\(controller.proxyGroups.count) groups · \(graph.edges.count) member references", attention: !graph.issues.isEmpty))
            rows += graph.issues.enumerated().map { Row(id: "Policy issue \($0.offset + 1)", status: "Check", detail: $0.element, attention: true) }
        } catch { rows.append(Row(id: "Policy membership", status: "Unavailable", detail: "The policy snapshot could not be read.", attention: true)) }
        do {
            let resources = try await controller.fetchProxyResources()
            for resource in resources {
                let measured = resource.proxies.filter { $0.latest != nil }
                let failed = measured.filter { $0.latest?.delay == 0 }.count
                rows.append(Row(id: "Nodes · " + resource.name, status: failed > 0 ? "Check measurements" : "Read",
                    detail: "\(resource.proxies.count) nodes · \(measured.count) measured · \(failed) zero-delay results. Historical measurements, not a live connectivity test.", attention: failed > 0))
            }
        } catch { rows.append(Row(id: "Node resources", status: "Unavailable", detail: "Resource metadata could not be read.", attention: true)) }
        do {
            for resource in try await controller.fetchRuleProviders() {
                rows.append(Row(id: "Rules · " + resource.name, status: "Read", detail: "\(resource.ruleCount) rules · \(resource.behavior)", attention: false))
            }
        } catch { rows.append(Row(id: "Rule resources", status: "Unavailable", detail: "Resource metadata could not be read.", attention: true)) }
        try Task.checkCancellation()
        guard generation == controller.runtimeGeneration, revision == profiles.activeProfileRevision,
              vm.runtimeState.isAPIReady, !vm.isToggling, !AppState.shared.isPerformingNetworkOperation else { throw CancellationError() }
        return Snapshot(generation: generation, revision: revision, capturedAt: Date(), rows: rows)
    }
}
