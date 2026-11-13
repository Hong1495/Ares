import Foundation

/// Bounded metadata only; never stores override documents, node credentials or network identity.
nonisolated struct SceneExecution: Codable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    let sceneID: UUID?
    let name: String
    let automatic: Bool
    let result: String
    let sections: [String]
    init(sceneID: UUID?, name: String, automatic: Bool, result: String, sections: [String]) {
        id = UUID(); date = Date(); self.sceneID = sceneID; self.name = name
        self.automatic = automatic; self.result = result; self.sections = sections
    }
}
nonisolated enum SceneExecutionHistory {
    static let limit = 100
    static func load(directory: URL) throws -> [SceneExecution] {
        let path = directory.appendingPathComponent("history.json")
        guard FileManager.default.fileExists(atPath: path.path) else { return [] }
        return try JSONDecoder().decode([SceneExecution].self, from: Data(contentsOf: path))
    }
    static func append(_ entry: SceneExecution, directory: URL) throws {
        let entries = Array(([entry] + (try load(directory: directory))).prefix(limit))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let path = directory.appendingPathComponent("history.json")
        try JSONEncoder().encode(entries).write(to: path, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
    }
}
