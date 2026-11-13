import Foundation

/// Owns the shutdown gate through the entire handoff, including asynchronous cleanup.
/// Failed preparation releases the gate; successful preparation stays locked until exit or abort.
@MainActor final class TerminationTransition {
    enum State: Equatable { case idle, preparing, prepared }
    private(set) var state: State = .idle
    var blocksOperations: Bool { state != .idle }

    func prepare(
        waitUntilIdle: () async -> Bool,
        restoreProxy: () async -> Bool,
        stopCore: () async -> Bool,
        stopDependents: () async -> Void,
        didPrepare: () -> Void
    ) async -> Bool {
        if state == .prepared { return true }
        guard state == .idle else { return false }
        state = .preparing
        var completed = false
        defer { state = completed ? .prepared : .idle }
        guard await waitUntilIdle(), !Task.isCancelled else { return false }
        // Once restoration starts, finish cleanup even if the initiating task is cancelled.
        guard await restoreProxy() else { return false }
        guard await stopCore() else { return false }
        await stopDependents()
        didPrepare()
        completed = true
        return true
    }

    func cancelHandoff() {
        // Never unlock an in-flight cleanup. Its caller must await it before aborting.
        if state == .prepared { state = .idle }
    }
}
