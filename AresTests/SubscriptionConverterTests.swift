import XCTest

final class SubscriptionConverterTests: XCTestCase {
    func testRealityPlaceholderIsNotEmitted() throws {
        let placeholder = "TO" + "DO"
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Ares/Services/SubscriptionConverter.swift"))

        XCTAssertFalse(source.contains("\"\(placeholder)\""))
        XCTAssertTrue(source.contains("public-key"))
        XCTAssertTrue(source.contains("short-id"))
        XCTAssertTrue(source.contains("flow"))
    }
}
