import Foundation

/// The listener must remain available until every referencing traffic path has moved.
nonisolated enum ListenerMigration {
    static func retire(
        migrateRoutes: () async -> Bool,
        migrateProxy: () async -> Bool,
        stopListener: () async -> Void
    ) async -> Bool {
        guard await migrateRoutes(), await migrateProxy() else { return false }
        await stopListener()
        return true
    }
}
