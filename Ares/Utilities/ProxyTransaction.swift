import Foundation

/// No system access: the caller supplies command execution and verified reads.
nonisolated enum ProxyTransaction {
    enum Outcome: Equatable { case committed, rolledBack, recoveryRequired }

    static func apply(
        write: () async -> Bool,
        verify: () async -> Bool,
        rollback: () async -> Bool,
        verifyRollback: () async -> Bool
    ) async -> Outcome {
        if await write(), await verify() { return .committed }
        if await rollback(), await verifyRollback() { return .rolledBack }
        return .recoveryRequired
    }
}
