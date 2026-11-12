import Foundation

/// Cumulative observed traffic, independent of the lifetime of UI application rows.
nonisolated struct ActivityTrafficLedger {
    private(set) var upload: Int64 = 0
    private(set) var download: Int64 = 0
    private var baseline: [String: (up: Int64, down: Int64)] = [:]

    mutating func record(_ connections: [Connection]) {
        for connection in connections {
            let previous = baseline[connection.id] ?? (0, 0)
            upload += max(0, connection.upload - previous.up)
            download += max(0, connection.download - previous.down)
            baseline[connection.id] = (connection.upload, connection.download)
        }
        // Retain IDs until explicit reset so a temporarily absent connection
        // cannot be counted again when monitoring resumes.
    }

    mutating func reset() {
        upload = 0
        download = 0
        // Preserve baselines: reset must not re-add the lifetime bytes of open connections.
    }
}
