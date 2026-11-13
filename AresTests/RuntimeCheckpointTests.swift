import XCTest

final class RuntimeCheckpointTests: XCTestCase {
    func testModeIsolationPrivatePermissionsAndBoundedReplacement() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("AresCheckpoint-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let normal = RuntimeCheckpoint(configuration: "secret: test-only", profileID: UUID(), profileRevision: "old",
            selections: ["Proxy": "Node B"], tunEnabled: false)
        let tun = RuntimeCheckpoint(configuration: "tun: {enable: true}", profileID: nil, profileRevision: "new",
            selections: [:], tunEnabled: true)
        try RuntimeCheckpointStore.save(normal, directory: dir)
        try RuntimeCheckpointStore.save(tun, directory: dir)
        XCTAssertEqual(try RuntimeCheckpointStore.load(directory: dir, tunEnabled: false), normal)
        XCTAssertEqual(try RuntimeCheckpointStore.load(directory: dir, tunEnabled: true), tun)
        for file in ["normal.json", "tun.json"] {
            let attributes = try FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent(file).path)
            XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        }
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: dir.path)[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        try RuntimeCheckpointStore.save(normal, directory: dir)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path).count, 2)
        try "{broken".write(to: dir.appendingPathComponent("normal.json"), atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try RuntimeCheckpointStore.load(directory: dir, tunEnabled: false))
        XCTAssertEqual(try RuntimeCheckpointStore.load(directory: dir, tunEnabled: true), tun)
    }
}
