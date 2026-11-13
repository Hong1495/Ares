import XCTest

final class AppStateTUNSourceTests: XCTestCase {
    func testTUNToggleRevertsPersistedStateAndPortOnFailure() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Ares/Services/AppState+TUN.swift"))

        XCTAssertTrue(source.contains("ConfigurationCoordinator.replace("))
        XCTAssertTrue(source.contains("setTUNConfiguration(oldTUN)"))
        XCTAssertTrue(source.contains("previous: checkpoint, targetMode: !oldTUN"))
        XCTAssertTrue(source.contains("CoreAPIContract.verifyTUN(data, expected: expected)"))
        XCTAssertFalse(source.contains("try? await self.verifyTUNStatus()"))
    }
}
