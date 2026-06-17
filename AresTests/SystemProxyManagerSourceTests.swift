import XCTest

final class SystemProxyManagerSourceTests: XCTestCase {
    func testAppleScriptFallbackUsesShellQuotedCommands() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Ares/Services/SystemProxyManager.swift"))

        XCTAssertTrue(source.contains("shellQuoted"))
        XCTAssertTrue(source.contains("shellCommand"))
        XCTAssertTrue(source.contains("AppleScriptEscaper.stringLiteral(shellCommands)"))
        XCTAssertFalse(source.contains("networksetup -setwebproxy '\\(service)'"))
        XCTAssertFalse(source.contains("networksetup -setproxybypassdomains '\\(service)' \\(bypassStr)"))
        XCTAssertFalse(source.contains("do shell script \"\\(shellCommands)\""))
    }
}
