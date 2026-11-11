import Foundation

/// A failed stop never permits another launch. Recovery requires the caller to
/// verify the previous core and its dependent traffic routing.
nonisolated enum RuntimeTransition {
    enum Outcome: Equatable { case committed, unchanged, restored, recoveryRequired }
    static func perform(
        stopCurrent: () async -> Bool,
        activateNew: () async -> Bool,
        stopNew: () async -> Bool,
        restorePrevious: () async -> Bool
    ) async -> Outcome {
        guard await stopCurrent() else { return .unchanged }
        if await activateNew() { return .committed }
        guard await stopNew() else { return .recoveryRequired }
        return await restorePrevious() ? .restored : .recoveryRequired
    }
}
