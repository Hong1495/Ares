import Foundation

/// A configuration which passed startup readback. Contains credentials: never log or export it.
nonisolated struct RuntimeCheckpoint: Codable, Sendable, Equatable {
    let schema: Int
    let configuration: String
    let profileID: UUID?
    let profileRevision: String
    let selections: [String: String]
    let tunEnabled: Bool
    let verifiedAt: Date

    init(configuration: String, profileID: UUID?, profileRevision: String,
         selections: [String: String], tunEnabled: Bool, verifiedAt: Date = Date()) {
        schema = 1
        self.configuration = configuration
        self.profileID = profileID
        self.profileRevision = profileRevision
        self.selections = selections
        self.tunEnabled = tunEnabled
        self.verifiedAt = verifiedAt
    }
}

/// Bounded, atomic recovery storage. One successful checkpoint per mode; no growing history.
nonisolated enum RuntimeCheckpointStore {
    enum Failure: Error { case incompatible }
    static func save(_ checkpoint: RuntimeCheckpoint, directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let destination = path(directory: directory, tunEnabled: checkpoint.tunEnabled)
        let data = try JSONEncoder().encode(checkpoint)
        // Atomic replacement lives in a private directory, including the temporary file.
        try data.write(to: destination, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
    }
    static func load(directory: URL, tunEnabled: Bool) throws -> RuntimeCheckpoint {
        let checkpoint = try JSONDecoder().decode(RuntimeCheckpoint.self,
            from: Data(contentsOf: path(directory: directory, tunEnabled: tunEnabled)))
        guard checkpoint.schema == 1, checkpoint.tunEnabled == tunEnabled else { throw Failure.incompatible }
        return checkpoint
    }
    private static func path(directory: URL, tunEnabled: Bool) -> URL {
        directory.appendingPathComponent(tunEnabled ? "tun.json" : "normal.json")
    }
}
