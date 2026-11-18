import Foundation
import Combine
import SubscriptionKit

@MainActor final class PolicyGroupsViewModel: ObservableObject {
    struct Context: Equatable {
        let profile: String
        let generation: UUID
        let readable: Bool
    }
    struct Runtime {
        let groups: [ProxyGroup]
        let nodes: [String: ProxyNode]
    }
    @Published private(set) var snapshot: PolicyGroupService.Snapshot?
    @Published private(set) var live: [ProxyGroup]?
    @Published private(set) var graph: PolicyGraph.Snapshot?
    @Published private(set) var capturedAt: Date?
    @Published private(set) var busy = false
    @Published private(set) var error: String?
    @Published var selection: String?
    @Published var message: String?
    private var request = UUID()
    private let context: @MainActor () -> Context
    private let configuration: @MainActor () async throws -> PolicyGroupService.Snapshot
    private let runtime: @MainActor () async throws -> Runtime

    init(context: @escaping @MainActor () -> Context = {
        .init(profile: ProfileService.shared.activeProfileRevision, generation: ClashController.shared.runtimeGeneration,
              readable: PolicyGroupService.canReadRuntime)
    }, configuration: @escaping @MainActor () async throws -> PolicyGroupService.Snapshot = { try await PolicyGroupService.load() },
         runtime: @escaping @MainActor () async throws -> Runtime = {
        let controller = ClashController.shared
        try await controller.fetchProxiesData()
        return .init(groups: controller.proxyGroups, nodes: controller.proxyNodes)
    }) {
        self.context = context; self.configuration = configuration; self.runtime = runtime
    }
    var selected: PolicyConfiguration.Group? { snapshot?.effective.first { $0.name == selection } }
    var references: [PolicyUsage.Reference] { snapshot?.usage?.references(to: selection ?? "") ?? [] }
    func invalidate(profileChanged: Bool = false) {
        request = UUID(); busy = false
        live = nil; graph = nil; capturedAt = nil; error = nil; message = nil
        if profileChanged { snapshot = nil; selection = nil }
    }
    func reload() async {
        let ticket = UUID(), baseline = context()
        request = ticket; busy = true
        defer { if request == ticket { busy = false } }
        guard !baseline.profile.isEmpty else {
            snapshot = nil; selection = nil; live = nil; graph = nil; capturedAt = nil; error = nil
            return
        }
        if !baseline.readable { live = nil; graph = nil; capturedAt = nil }
        do {
            let saved = try await configuration()
            guard current(ticket, baseline) else { return }
            snapshot = saved; error = nil
            if let selection, !saved.effective.contains(where: { $0.name == selection }) { self.selection = nil }
        } catch {
            guard current(ticket, baseline) else { return }
            snapshot = nil; live = nil; graph = nil; capturedAt = nil
            self.error = "Configuration unavailable. Reload to try again."
            return
        }
        guard baseline.readable else { return }
        do {
            let result = try await runtime()
            guard current(ticket, baseline) else { return }
            live = result.groups; graph = PolicyGraph.inspect(groups: result.groups, nodes: result.nodes); capturedAt = Date()
        } catch {
            guard current(ticket, baseline) else { return }
            live = nil; graph = nil; capturedAt = nil
            self.error = "Saved configuration loaded. Runtime readback is unavailable."
        }
    }
    private func current(_ ticket: UUID, _ baseline: Context) -> Bool {
        request == ticket && context() == baseline && !Task.isCancelled
    }
}
