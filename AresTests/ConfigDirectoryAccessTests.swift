import XCTest
import Darwin

final class ConfigDirectoryAccessTests: XCTestCase {
    func testRepairOnlyTouchesExactDirectoryAndConfig() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        let directory = base.appendingPathComponent("Ares/clash_root")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: base)
        }
        let config = directory.appendingPathComponent("config.yaml")
        try "original".write(to: config, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        XCTAssertThrowsError(try ConfigDirectoryAccess.verifyWritable(directory))
        let command = try ConfigDirectoryAccess.repairCommand(directory: directory, userID: getuid())
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = ["-c", command]
        try proc.run()
        proc.waitUntilExit()
        XCTAssertEqual(proc.terminationStatus, 0)
        try ConfigDirectoryAccess.verifyWritable(directory)
        XCTAssertEqual(try String(contentsOf: config, encoding: .utf8), "original")
        try "replacement".write(to: config, atomically: true, encoding: .utf8)
        XCTAssertEqual(try String(contentsOf: config, encoding: .utf8), "replacement")
    }

    func testRejectsOtherDirectoriesAndSymlinks() throws {
        XCTAssertThrowsError(try ConfigDirectoryAccess.repairCommand(directory: URL(fileURLWithPath: "/tmp/Other/clash_root"), userID: getuid()))
        XCTAssertThrowsError(try ConfigDirectoryAccess.repairCommand(directory: URL(fileURLWithPath: "/tmp/Ares/clash_user"), userID: getuid()))
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: base.appendingPathComponent("Ares"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let directory = base.appendingPathComponent("Ares/clash_root")
        try FileManager.default.createSymbolicLink(at: directory, withDestinationURL: base)
        XCTAssertThrowsError(try ConfigDirectoryAccess.repairCommand(directory: directory, userID: getuid()))
    }

    func testConfigSymlinkCannotChangeExternalFilePermissions() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let directory = base.appendingPathComponent("Ares/clash_root")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let external = base.appendingPathComponent("external")
        try Data().write(to: external)
        try FileManager.default.setAttributes([.posixPermissions: 0o400], ofItemAtPath: external.path)
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("config.yaml"), withDestinationURL: external)
        let command = try ConfigDirectoryAccess.repairCommand(directory: directory, userID: getuid())
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = ["-c", command]
        try proc.run()
        proc.waitUntilExit()
        XCTAssertNotEqual(proc.terminationStatus, 0)
        let attrs = try FileManager.default.attributesOfItem(atPath: external.path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o400)
    }
}
