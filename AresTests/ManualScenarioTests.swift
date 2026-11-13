import XCTest

final class ManualScenarioTests: XCTestCase {
    func testCaptureInstallAndRestoreMissingKeys() throws {
        let suite = "AresSceneTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let id = UUID(), other = UUID()
        defaults.set("unrelated", forKey: "dnsOverrides." + other.uuidString)
        let before = ScenarioSettings.capture(profile: id, defaults: defaults)
        let target = ScenarioSettings(localRules: "MATCH,DIRECT", dns: "{}", policy: nil, egress: "")
        target.install(profile: id, defaults: defaults)
        XCTAssertEqual(ScenarioSettings.capture(profile: id, defaults: defaults), target)
        before.install(profile: id, defaults: defaults)
        XCTAssertNil(defaults.object(forKey: "localRules"))
        XCTAssertNil(defaults.object(forKey: "dnsOverrides." + id.uuidString))
        XCTAssertEqual(defaults.string(forKey: "dnsOverrides." + other.uuidString), "unrelated")
    }
    func testDiffRetainsAbsentVersusEmptyAndDoesNotExposeSecrets() {
        let before = ScenarioSettings(localRules: nil, dns: nil, policy: nil, egress: nil)
        let after = ScenarioSettings(localRules: "", dns: "secret-resolver-token", policy: nil, egress: nil)
        let rows = after.differences(from: before)
        XCTAssertEqual(rows.count, 2)
        XCTAssertFalse(rows.map { $0.before + $0.after }.joined().contains("secret"))
        XCTAssertEqual(before.differences(from: after).first?.after, "Restore inheritance")
    }
    func testPrivateAtomicLibraryAndDuplicateNames() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ares-scenes-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertEqual(try ScenarioLibrary.load(directory: directory), [])
        let id = UUID(), settings = ScenarioSettings(localRules: nil, dns: nil, policy: nil, egress: nil)
        let item = try ManualScenario(name: " Office ", profileID: id, sourceRevision: "revision", settings: settings)
        try ScenarioLibrary.save([item], directory: directory)
        XCTAssertEqual(try ScenarioLibrary.load(directory: directory), [item])
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? Int, 0o700)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("scenarios.json").path)[.posixPermissions] as? Int, 0o600)
        let duplicate = try ManualScenario(name: "office", profileID: id, sourceRevision: "r", settings: settings)
        XCTAssertThrowsError(try ScenarioLibrary.save([item, duplicate], directory: directory))
        XCTAssertEqual(try ScenarioLibrary.load(directory: directory), [item])
        let other = try ManualScenario(name: "Office", profileID: UUID(), sourceRevision: "r", settings: settings)
        try ScenarioLibrary.save([item, other], directory: directory)
        XCTAssertEqual(try ScenarioLibrary.load(directory: directory).count, 2)
        try Data("broken".utf8).write(to: directory.appendingPathComponent("scenarios.json"))
        XCTAssertThrowsError(try ScenarioLibrary.load(directory: directory))
    }
    func testInvalidNamesAndSchemaFail() throws {
        let settings = ScenarioSettings(localRules: nil, dns: nil, policy: nil, egress: nil)
        for name in ["", "   ", "a\nb", String(repeating: "x", count: 81)] {
            XCTAssertThrowsError(try ManualScenario(name: name, profileID: UUID(), sourceRevision: "r", settings: settings))
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ares-scenes-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(#"{"schema":9,"scenarios":[]}"#.utf8).write(to: directory.appendingPathComponent("scenarios.json"))
        XCTAssertThrowsError(try ScenarioLibrary.load(directory: directory))
    }
}
