import XCTest

final class AppleScriptEscaperTests: XCTestCase {
    func testStringLiteralEscapesAppleScriptSensitiveCharacters() {
        let escaped = AppleScriptEscaper.stringLiteral("a \"quote\" \\ path\nnext\rline")

        XCTAssertEqual(escaped, "a \\\"quote\\\" \\\\ path\\nnext\\rline")
    }
}
