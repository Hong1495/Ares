import XCTest

final class ProcessOwnershipSourceTests: XCTestCase {
    private func source(_ path: String) throws -> String {
        try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(path), encoding: .utf8)
    }

    func testCoreNeverKillsDiscoveredPortOccupants() throws {
        let core = try source("Ares/Services/ClashServiceActor.swift")
        XCTAssertFalse(core.contains("killProcess("))
        XCTAssertFalse(core.contains("performPortCleanup"))
        XCTAssertFalse(core.contains("currentProcessPID"))
        XCTAssertTrue(core.contains("if let proc = process, proc.isRunning"))
        XCTAssertTrue(core.contains("guard !proc.isRunning else"))
        XCTAssertTrue(core.contains("guard !lifecycleBusy else"))
    }

    func testPrivilegeProbeDoesNotExecutePkill() throws {
        let privileges = try source("Ares/Services/PrivilegeService.swift")
        XCTAssertFalse(privileges.contains("/usr/bin/pkill"))
        XCTAssertFalse(privileges.contains("ares_dummy_process_check"))
    }
}
