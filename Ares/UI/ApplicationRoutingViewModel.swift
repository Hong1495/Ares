import Foundation
import Combine
import SubscriptionKit

@MainActor
final class ApplicationRoutingViewModel: ObservableObject {
    @Published private(set) var snapshot: ApplicationRoutingService.Snapshot?
    @Published private(set) var connections: [Connection] = []
    @Published private(set) var capturedAt: Date?
    @Published private(set) var addedPaths: [String] = []
    @Published var selectedAppID: String?
    @Published var selectedPaths = Set<String>()
    @Published var target: ApplicationRouting.SelectionRoute = .inherited
    @Published private(set) var busy = false
    @Published private(set) var undo: ApplicationRoutingService.Undo?
    @Published var error: String?
    @Published private(set) var message: String?
    private var request = UUID()
    private var connectionRequest = UUID()
    private var initialPaths: [String] = []
    private var observedPaths = Set<String>()

    var localRules: String { snapshot?.rules ?? "" }
    var applications: [ApplicationRoutingPresentation.Application] {
        let managed = ApplicationRouting.paths(in: localRules) + addedPaths
        let identities = Set(ApplicationRoutingPresentation.applications(paths: managed).map(\.id))
        let helpers = observedPaths.filter {
            identities.contains(ConnectionIdentity(path: $0, process: nil, source: "").key)
        }
        return ApplicationRoutingPresentation.applications(paths: managed + helpers)
    }
    var discovered: [ApplicationRoutingPresentation.Application] {
        ApplicationRoutingPresentation.applications(paths: Array(observedPaths))
    }
    var selectedApplication: ApplicationRoutingPresentation.Application? {
        applications.first { $0.id == selectedAppID }
    }
    var matching: [Connection] { connections.filter { selectedPaths.contains($0.metadata.processPath ?? "") } }
    var canApply: Bool {
        guard snapshot != nil, !selectedPaths.isEmpty, !busy, target != .mixed else { return false }
        let routes = ApplicationRouting.localRoutes(in: localRules)
        return selectedPaths.contains { path in
            switch target {
            case .inherited: return routes[path] != nil
            case .target(let target): return routes[path]?.target != target || (routes[path]?.entries ?? 0) > 1
            case .mixed: return false
            }
        }
    }

    func route(paths: [String]) -> ApplicationRouting.SelectionRoute {
        ApplicationRouting.selectionRoute(paths: paths, rules: localRules)
    }

    func verification(paths: [String], ruleMode: Bool) -> ApplicationRouting.Verification {
        guard snapshot != nil else { return .unavailable }
        return ApplicationRouting.verification(paths: paths, rules: localRules,
            observations: ApplicationRoutingPresentation.observations(connections), available: capturedAt != nil,
            ruleMode: ruleMode, notBefore: ApplicationRoutingService.verificationSince)
    }

    func start(paths: [String]) async {
        initialPaths = paths.filter(ApplicationRouting.validPath)
        addedPaths = initialPaths
        await reload()
        if let first = initialPaths.first {
            selectedAppID = ConnectionIdentity(path: first, process: nil, source: "").key
            selectApplication()
            selectedPaths = Set(initialPaths.filter { ConnectionIdentity(path: $0, process: nil, source: "").key == selectedAppID })
            syncTarget()
        }
    }

    func selectApplication() {
        guard let app = selectedApplication else { selectedPaths = []; target = .inherited; return }
        selectedPaths = Set(app.paths)
        syncTarget()
        message = nil
    }

    func select(_ id: String?) {
        selectedAppID = id
        selectApplication()
    }

    func setPath(_ path: String, included: Bool) {
        if included { selectedPaths.insert(path) } else { selectedPaths.remove(path) }
        syncTarget()
    }

    private func syncTarget() { target = route(paths: selectedPaths.sorted()) }

    func add(paths: [String]) {
        let paths = paths.filter(ApplicationRouting.validPath)
        addedPaths = Array(Set(addedPaths + paths)).sorted()
        guard let first = paths.first else { return }
        selectedAppID = ConnectionIdentity(path: first, process: nil, source: "").key
        selectedPaths = Set(paths.filter { ConnectionIdentity(path: $0, process: nil, source: "").key == selectedAppID })
        syncTarget()
        message = nil
    }

    func invalidateRuntime() {
        request = UUID()
        connectionRequest = UUID()
        connections = []; capturedAt = nil
    }

    func reload() async {
        guard !busy else { return }
        let revision = UUID(); request = revision
        do {
            let result = try await ApplicationRoutingService.load()
            guard request == revision, !Task.isCancelled else { return }
            let changed = snapshot?.rules != result.rules || snapshot?.targets != result.targets
            snapshot = result; error = nil
            if let selectedApplication, changed {
                selectedPaths.formIntersection(selectedApplication.paths)
                syncTarget()
            }
        } catch {
            guard request == revision, !Task.isCancelled else { return }
            snapshot = nil; connections = []; capturedAt = nil
            self.error = "Configuration unavailable. Reload to try again."
        }
        await readConnections()
    }

    func readConnections() async {
        guard !busy else { return }
        let revision = request
        let observation = UUID(); connectionRequest = observation
        do {
            let rows = try await ApplicationRoutingService.connections()
            guard request == revision, connectionRequest == observation, !Task.isCancelled else { return }
            connections = rows; capturedAt = Date()
            observedPaths.formUnion(rows.compactMap { $0.metadata.processPath }.filter(ApplicationRouting.validPath))
        } catch {
            guard request == revision, connectionRequest == observation, !Task.isCancelled else { return }
            connections = []; capturedAt = nil
        }
    }

    func apply() async {
        guard let snapshot, canApply else { return }
        let paths = selectedPaths.sorted()
        let destination: String?
        switch target {
        case .inherited: destination = nil
        case .target(let name): destination = name
        case .mixed: return
        }
        busy = true; request = UUID(); error = nil
        do {
            let change = try await ApplicationRoutingService.apply(paths: paths, target: destination, snapshot: snapshot)
            if let change { undo = change }
            addedPaths = Array(Set(addedPaths + paths)).sorted()
            message = destination == nil ? "Local override removed. New connections follow rules." : "Saved. Waiting for new connections to verify."
            connections = []; capturedAt = nil
        } catch { self.error = error.localizedDescription }
        busy = false
        // Load fresh state after stale-draft rejection; never retry a mutation.
        let failure = error
        await reload()
        if let failure { error = failure }
    }

    func revert() async {
        guard let undo, !busy else { return }
        busy = true; request = UUID(); error = nil
        if await ApplicationRoutingService.undo(undo) {
            self.undo = nil; message = "Previous rules restored. Waiting for new connections."
            connections = []; capturedAt = nil
        } else { error = "Undo unavailable after another rule or subscription change." }
        busy = false
        let failure = error
        await reload()
        if let failure { error = failure }
    }
}
