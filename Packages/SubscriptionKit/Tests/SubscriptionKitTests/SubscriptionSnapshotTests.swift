import XCTest
@testable import SubscriptionKit

final class SubscriptionSnapshotTests: XCTestCase {
    func testStoppedCoreNeedsOnlySavedYAML() throws {
        let nodes = (1...32).map { "  - {name: Node \($0), type: vless, server: example.invalid, port: 443, uuid: private}" }.joined(separator: "\n")
        let yaml = "proxies:\n" + nodes + "\nproxy-groups:\n  - name: Select\n    type: select\n    proxies: [Node 1, Auto]\n  - name: Auto\n    type: url-test\n    proxies: [Node 1, Node 2]"
        let snapshot = try SubscriptionSnapshot.parse(yaml)
        XCTAssertEqual(snapshot.nodes.count, 32)
        XCTAssertEqual(snapshot.groups.count, 2)
        XCTAssertEqual(snapshot.groups[0].members, ["Node 1", "Auto"])
    }
    func testBlockQuotedUnicodeAndAnchors() throws {
        let snapshot = try SubscriptionSnapshot.parse("""
        proxies:
        - name: '香港: #1'
          type: vless
          port: 443
        proxy-groups:
        - name: Select
          type: select
          proxies: &members ['香港: #1', DIRECT]
        - name: Auto
          type: url-test
          proxies: *members
        """)
        XCTAssertEqual(snapshot.nodes[0].name, "香港: #1")
        XCTAssertEqual(snapshot.groups[1].members, ["香港: #1", "DIRECT"])
    }
    func testJSONAndUngroupedNodes() throws {
        let snapshot = try SubscriptionSnapshot.parse(#"{"proxies":[{"name":"Node","type":"vless"}]}"#)
        XCTAssertEqual(snapshot.groups[0].members, ["Node"])
    }
    func testProvidersAreExplicitAndNeverFetched() throws {
        let snapshot = try SubscriptionSnapshot.parse("proxy-providers: {remote: {type: http, url: 'https://example.invalid/private'}}\nproxy-groups: [{name: Remote, type: select, use: [remote]}]")
        XCTAssertEqual(snapshot.providerCount, 1)
        XCTAssertTrue(snapshot.nodes.isEmpty)
        XCTAssertTrue(snapshot.groups[0].members.isEmpty)
    }
    func testMalformedYAMLThrows() { XCTAssertThrowsError(try SubscriptionSnapshot.parse("proxies: [")) }
    func testDuplicateNamesDoNotCreateDuplicateViewIdentities() throws {
        let snapshot = try SubscriptionSnapshot.parse("proxies: [{name: One, type: ss}, {name: One, type: ss}]\nproxy-groups: [{name: Select, type: select, proxies: [One, One]}]")
        XCTAssertEqual(snapshot.nodes.count, 1)
        XCTAssertEqual(snapshot.groups[0].members, ["One"])
    }
    func testSavedProfileOnDiskWithoutServices() throws {
        guard let path = ProcessInfo.processInfo.environment["ARES_READONLY_PROFILE"] else { throw XCTSkip("Optional local read-only acceptance fixture") }
        let snapshot = try SubscriptionSnapshot.parse(String(contentsOfFile: path, encoding: .utf8))
        XCTAssertEqual(snapshot.nodes.count, 32)
        XCTAssertEqual(snapshot.groups.count, 2)
        XCTAssertTrue(snapshot.nodes.allSatisfy { $0.type == "vless" })
    }
}
