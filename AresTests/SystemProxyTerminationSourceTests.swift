import XCTest

final class SystemProxyTerminationSourceTests: XCTestCase {
    func testTerminationCleanupRestoresSnapshotBeforeDisabling() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Ares/Services/SystemProxyManager.swift"))

        XCTAssertTrue(source.contains("return restoreSnapshotSync(for: getNetworkServicesSync())"))
        XCTAssertTrue(source.contains("guard UserDefaults.standard.data(forKey: snapshotKey) != nil else { return true }"))
        XCTAssertTrue(source.contains("equivalent(actual, snapshot)"))
        XCTAssertFalse(source.contains("snapshotUsesAresProxy"))
        XCTAssertFalse(source.contains("proxiesAreDisabledSync"))
    }

    func testTerminationRefusesToStopCoreWhenProxyCleanupFails() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Ares/AresApp.swift"))

        let cleanupGuard = try XCTUnwrap(source.range(of: "guard SystemProxyManager.shared.disableAllProxiesSync() else"))
        let stopCore = try XCTUnwrap(source.range(of: "await ClashViewModel.shared.stopCore()"))
        XCTAssertLessThan(cleanupGuard.lowerBound, stopCore.lowerBound)
        XCTAssertTrue(source.contains("sender.reply(toApplicationShouldTerminate: isSafeToTerminate)"))
    }
}
