import XCTest

final class AppStateTUNSourceTests: XCTestCase {
    func testTUNToggleRevertsPersistedStateAndPortOnFailure() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Ares/Services/AppState+TUN.swift"))

        XCTAssertTrue(source.contains("let succeeded = await self.performTUNToggleWork(newState: newTUN)"))
        XCTAssertTrue(source.contains("self.tunEnabled = oldTUN"))
        XCTAssertTrue(source.contains("UserDefaults.standard.set(oldTUN, forKey: DefaultsKeys.tunEnabled)"))
        XCTAssertTrue(source.contains("self.clashController.updatePort(tunEnabled: oldTUN)"))
        XCTAssertTrue(source.contains("return false"))
    }
}
