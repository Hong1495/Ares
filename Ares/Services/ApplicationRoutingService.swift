import Foundation
import SubscriptionKit

@MainActor enum ApplicationRoutingService {
    struct Snapshot {
        let policy: PolicyGroupService.Snapshot
        let rules: String
        let evidence: [String]
        let evidenceSource: String
        let targets: [String]
    }
    struct Undo {
        let previous: String
        let applied: String
        let revision: String
    }
    static func load() async throws -> Snapshot {
        let policy = try await PolicyGroupService.load()
        var evidence = try ApplicationRouting.configuredRules(policy.source)
        evidence = RuleDraftDocument(policy.localRules).rules.compactMap(\.rule) + evidence
        var source = "Saved local + subscription rules"
        if PolicyGroupService.canReadRuntime, let checkpoint = try? ClashViewModel.shared.recoveryCheckpoint() {
            evidence = try ApplicationRouting.configuredRules(checkpoint.configuration)
            source = "Verified running configuration"
        }
        let catalog = try PolicyConfiguration.catalog(policy.source)
        return Snapshot(policy: policy, rules: policy.localRules, evidence: evidence, evidenceSource: source,
                        targets: Array(Set(["DIRECT", "REJECT"] + policy.effective.map(\.name) + catalog.nodes)).sorted())
    }
    static func apply(paths: [String], target: String?, snapshot: Snapshot) async throws -> Undo? {
        let policy = snapshot.policy
        guard policy.stored == (UserDefaults.standard.string(forKey: policy.storageKey) ?? "{}") else {
            throw PolicyConfiguration.Failure.invalid("Policy groups changed. Reload before applying.")
        }
        if let target, !snapshot.targets.contains(target) { throw PolicyConfiguration.Failure.invalid("The routing target is no longer available.") }
        let draft = try ApplicationRouting.replacing(snapshot.rules, paths: paths, target: target)
        guard draft != snapshot.rules else { return nil }
        guard await LocalRulesService.apply(draft, expectedRevision: policy.revision, expectedRules: snapshot.rules, expectedPolicy: (policy.storageKey, policy.stored)) else {
            throw PolicyConfiguration.Failure.invalid(AppState.shared.lastOperationError ?? "Another operation is in progress.")
        }
        return Undo(previous: snapshot.rules, applied: draft, revision: policy.revision)
    }
    static func undo(_ undo: Undo) async -> Bool {
        await LocalRulesService.apply(undo.previous, expectedRevision: undo.revision, expectedRules: undo.applied)
    }
    /// Use core-reported process identity for verification; OS display attribution is not proof of a rule match.
    static func connections() async throws -> [Connection] {
        guard PolicyGroupService.canReadRuntime else { throw URLError(.notConnectedToInternet) }
        let generation = ClashController.shared.runtimeGeneration
        let json = try await ClashController.shared.fetchConnections()
        let rows = ConnectionSnapshot.decode(try JSONSerialization.data(withJSONObject: json))
        guard generation == ClashController.shared.runtimeGeneration, PolicyGroupService.canReadRuntime else { throw CancellationError() }
        return rows.filter { !$0.identity.isAres }
    }
}
