import Foundation

/// Common state machine for settings, subscription and mode replacement.
/// All callbacks run in the caller's actor context. Failed cleanup never starts another core.
nonisolated enum ConfigurationTransition {
    enum Outcome: Equatable {
        case committed, preparationFailed, unchanged, restored, recoveryRequired
    }

    static func perform(
        prepare: () async throws -> Void,
        stop: () async -> Bool,
        activate: () async -> Bool,
        stopFailed: () async -> Bool,
        restore: () async -> Bool,
        undoPreparation: () async -> Bool
    ) async -> Outcome {
        do { try await prepare(); try Task.checkCancellation() }
        catch { return await undoPreparation() ? .preparationFailed : .recoveryRequired }
        guard await stop() else {
            return await undoPreparation() ? .unchanged : .recoveryRequired
        }
        if !Task.isCancelled, await activate() { return .committed }
        guard await stopFailed() else { return .recoveryRequired }
        // Recovery must still run when the initiating UI task was cancelled.
        return await restore() ? .restored : .recoveryRequired
    }
}
