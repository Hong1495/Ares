import XCTest

final class SystemProxyTerminationSourceTests: XCTestCase {
    func testTerminationCleanupRestoresSnapshotBeforeDisabling() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Ares/Services/SystemProxyManager.swift"))

        XCTAssertTrue(source.contains("restoreSnapshotSync(for: priorityServices)"))
        XCTAssertTrue(source.contains("""
        if restoreSnapshotSync(for: priorityServices) {
                    return
                }
        """))
    }
}
