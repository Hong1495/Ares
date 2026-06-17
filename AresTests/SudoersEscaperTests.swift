import XCTest

final class SudoersEscaperTests: XCTestCase {
    func testCommandPathEscapesWhitespaceAndQuotes() {
        XCTAssertEqual(
            SudoersEscaper.commandPath("/Users/me/Application Support/Ares/Core/mi\"ho'mo"),
            "/Users/me/Application\\ Support/Ares/Core/mi\\\"ho\\'mo"
        )
    }

    func testGeneratedRuleWithEscapedCommandPathPassesVisudo() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sudoers = directory.appendingPathComponent("ares_rules")
        let line = "\(SudoersEscaper.user(NSUserName())) ALL=(root) NOPASSWD: /tmp/A\\ B/mihomo\n"
        try line.write(to: sudoers, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/visudo")
        process.arguments = ["-cf", sudoers.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)
    }

    func testEscapedPathMatchesGeneratedSudoersContent() {
        let path = "/Users/me/Library/Application Support/Ares/Core/mihomo"
        let escapedPath = SudoersEscaper.commandPath(path)
        let content = "hong ALL=(root) NOPASSWD: \(escapedPath)\n"

        XCTAssertTrue(content.contains(escapedPath))
        XCTAssertFalse(content.contains(path))
    }
}
