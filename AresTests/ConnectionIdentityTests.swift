import XCTest

final class ConnectionIdentityTests: XCTestCase {
    func testProxyCoreTrafficIsExcludedFromActivity() {
        for path in ["/Users/example/Library/Application Support/Ares/Core/mihomo", "/Applications/Ares.app/Contents/Resources/clash-meta", "/usr/local/bin/mihomo"] {
            XCTAssertTrue(ConnectionIdentity(path: path, process: nil, source: "127.0.0.1").isAres)
        }
        XCTAssertTrue(ConnectionIdentity(path: nil, process: "mihomo", source: "127.0.0.1").isAres)
        XCTAssertFalse(ConnectionIdentity(path: "/Applications/mihomo-tools.app/Contents/MacOS/helper", process: "helper", source: "").isAres)
        XCTAssertFalse(ConnectionIdentity(path: nil, process: "mihomo-helper", source: "").isAres)
    }
    func testHelperUsesOuterAppAndProcessNameFallback() {
        let helper = ConnectionIdentity(path: "/Applications/Browser.app/Contents/Frameworks/Helper.app/Contents/MacOS/Helper", process: "Helper", source: "127.0.0.1")
        XCTAssertEqual(helper.name, "Browser")
        XCTAssertEqual(helper.iconPath, "/Applications/Browser.app")
        XCTAssertEqual(ConnectionIdentity(path: "", process: "curl", source: "127.0.0.1").name, "curl")
        XCTAssertFalse(ConnectionIdentity(path: "/usr/bin/shares", process: nil, source: "").isAres)
    }
    func testMissingIdentityRetainedWithoutFakeIcon() {
        let json = #"{"connections":[{"id":"1","metadata":{"network":"tcp","type":"HTTPS","sourceIP":"127.0.0.1","sourcePort":50123,"destinationPort":"443","processPath":"","process":"curl"},"download":100}]}"#
        let connections = ConnectionSnapshot.decode(Data(json.utf8))
        XCTAssertEqual(connections.count, 1)
        XCTAssertEqual(connections.first?.processName, "curl")
        XCTAssertEqual(connections.first?.metadata.sourcePort, "50123")
        let unknown = ConnectionIdentity(path: nil, process: nil, source: "192.168.1.2")
        XCTAssertNil(unknown.iconPath)
        XCTAssertEqual(unknown.name, "Unidentified · 192.168.1.2")
    }
    func testExactSocketMatchRejectsWrongPeerAndAmbiguity() {
        let metadata = ConnectionMetadata(network: "tcp", type: "HTTPS", sourceIP: "127.0.0.1", destinationIP: "1.2.3.4", sourcePort: "50001", destinationPort: "443", host: "", processPath: "", inboundIP: "127.0.0.1", inboundPort: "7890")
        let owners = SocketOwner.parse("p123\ncBrowser\nf10\nPTCP\nn127.0.0.1:50001->127.0.0.1:7890\np456\ncOther\nf20\nPTCP\nn127.0.0.1:50001->127.0.0.1:9999\n")
        XCTAssertEqual(SocketOwner.match(metadata, in: owners)?.pid, 123)
        XCTAssertNil(SocketOwner.match(metadata, in: Array(owners.dropFirst())))
        let collision = SocketOwner(pid: 789, process: "Other", network: "tcp", local: "127.0.0.1:50001", peer: "127.0.0.1:7890")
        XCTAssertNil(SocketOwner.match(metadata, in: owners + [collision]))
    }
    func testTUNIPv6AndOriginalEditorClassifications() {
        let metadata = ConnectionMetadata(network: "udp", type: "TUN", sourceIP: "::1", destinationIP: "2001:db8::1", sourcePort: "50002", destinationPort: "443", host: "", processPath: nil)
        let owners = SocketOwner.parse("p123\ncBrowser\nf10\nPUDP\nn[::1]:50002->[2001:db8::1]:443\n")
        XCTAssertEqual(SocketOwner.match(metadata, in: owners)?.pid, 123)
        XCTAssertEqual(ConnectionIdentity(path: "/Users/example/.cursor/extensions/test/server", process: nil, source: "").name, "Cursor")
        XCTAssertEqual(ConnectionIdentity(path: "/Users/example/.vscode/extensions/test/server", process: nil, source: "").name, "Visual Studio Code")
    }
}
