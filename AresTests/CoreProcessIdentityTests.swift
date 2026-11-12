import XCTest

final class CoreProcessIdentityTests: XCTestCase {
    let support = URL(fileURLWithPath: "/Users/example/Library/Application Support/Ares")
    let binary = "/old build/Ares.app/Contents/Resources/clash-meta"
    func identity(_ command: String, uid: Int = 0, date: String = "Wed Nov 11 15:04:49 2026") -> CoreProcessIdentity {
        CoreProcessIdentity(line: "5179 \(uid) \(date)     \(command)")!
    }
    func testRecognizesLegacyRootCoreAndSudoWrapper() {
        let command = "\(binary) -d \(support.path)/clash_root"
        XCTAssertTrue(identity(command).belongsToAres(support: support, userID: 501))
        XCTAssertTrue(identity("/usr/bin/sudo -n " + command).belongsToAres(support: support, userID: 501))
    }
    func testRecognizesManagedCoreAndUserCore() {
        XCTAssertTrue(identity("\(support.path)/Core/mihomo -d \(support.path)/clash_user", uid: 501).belongsToAres(support: support, userID: 501))
    }
    func testRejectsOtherClientsAndOtherUsers() {
        for command in ["/Applications/Clash Verge.app/Contents/MacOS/mihomo -d \(support.path)/clash_root", "\(binary) -d /tmp/other", "\(binary) -d \(support.path)/clash_root-other", "/bin/sh -c \(binary) -d \(support.path)/clash_root"] {
            XCTAssertFalse(identity(command).belongsToAres(support: support, userID: 501))
        }
        XCTAssertFalse(identity("\(binary) -d \(support.path)/clash_user", uid: 502).belongsToAres(support: support, userID: 501))
    }
    func testPIDReuseChangesIdentity() {
        let command = "\(binary) -d \(support.path)/clash_root"
        XCTAssertNotEqual(identity(command), identity(command, date: "Thu Nov 12 15:04:49 2026"))
    }
    func testMalformedProcessLinesAreRejected() {
        for line in ["", "1 0 Wed Nov 11 15:04:49 2026 /sbin/launchd", "bad pid", "0 0 Wed Nov 11 15:04:49 2026 core"] {
            XCTAssertNil(CoreProcessIdentity(line: line))
        }
    }
    func testShellLiteralEscapesApostrophe() {
        XCTAssertEqual(CoreProcessIdentity.shellQuote("a'b$(x)"), "'a'\\''b$(x)'")
    }
}
