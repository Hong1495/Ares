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
                    return true
                }
        """))
        XCTAssertTrue(source.contains("proxiesAreDisabledSync(for: priorityServices)"))
        XCTAssertTrue(source.contains("snapshots.values.contains(where: snapshotUsesAresProxy)"))
    }

    func testTerminationRefusesToStopCoreWhenProxyCleanupFails() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Ares/AresApp.swift"))

        let cleanupGuard = try XCTUnwrap(source.range(of: "guard SystemProxyManager.shared.disableAllProxiesSync() else"))
        let stopCore = try XCTUnwrap(source.range(of: "await ClashViewModel.shared.stop()"))
        XCTAssertLessThan(cleanupGuard.lowerBound, stopCore.lowerBound)
        XCTAssertTrue(source.contains("sender.reply(toApplicationShouldTerminate: isSafeToTerminate)"))
    }
}
