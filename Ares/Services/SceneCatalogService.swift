import Foundation
import SubscriptionKit

/// Read-only selection catalog. Runtime groups are used only for the matching subscription generation.
@MainActor enum SceneCatalogService {
    struct Catalog {
        let groups: [ProxyGroup]
        let live: Bool
        let revision: String
    }
    static func load() async throws -> Catalog {
        let profiles = ProfileService.shared, vm = ClashViewModel.shared, controller = ClashController.shared
        let revision = profiles.activeProfileRevision
        guard let path = profiles.activeProfile?.path else { throw URLError(.fileDoesNotExist) }
        if vm.runtimeState.isAPIReady && !vm.isToggling && vm.appliedProfileRevision == revision {
            let generation = controller.runtimeGeneration
            try await controller.fetchProxiesData()
            guard revision == profiles.activeProfileRevision, generation == controller.runtimeGeneration,
                  vm.runtimeState.isAPIReady, !vm.isToggling,
                  vm.appliedProfileRevision == revision else { throw CancellationError() }
            return Catalog(groups: controller.proxyGroups.filter(\.supportsManualSelection).sorted { $0.name < $1.name }, live: true, revision: revision)
        }
        let policy = profiles.activeProfileID.flatMap { UserDefaults.standard.string(forKey: "policyGroupOverrides." + $0.uuidString) } ?? "{}"
        let groups = try await Task.detached {
            let source = try String(contentsOf: path, encoding: .utf8)
            return try PolicyConfiguration.read(PolicyConfiguration.preview(source: source, overrides: policy)).compactMap { group -> ProxyGroup? in
                let type: String
                switch group.type { case "select": type = "Selector"; case "url-test": type = "URLTest"; case "fallback": type = "Fallback"; default: return nil }
                return ProxyGroup(name: group.name, type: type, all: group.members)
            }
        }.value
        guard revision == profiles.activeProfileRevision else { throw CancellationError() }
        return Catalog(groups: groups.sorted { $0.name < $1.name }, live: false, revision: revision)
    }
}
