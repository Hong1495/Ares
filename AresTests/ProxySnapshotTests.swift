import XCTest

final class ProxySnapshotTests: XCTestCase {
    func testNodesDoNotRequireLatencyHistory() throws {
        let data = Data(#"{"proxies":{"Node":{"type":"VLESS"},"Proxy":{"type":"Selector","all":["Node"],"now":"Node"}}}"#.utf8)
        let result = try ProxySnapshot.decode(data)
        XCTAssertEqual(result.nodes["Node"]?.type, "VLESS")
        XCTAssertNil(result.nodes["Node"]?.delay)
        XCTAssertEqual(result.groups.first?.all, ["Node"])
    }

    func testLatestDelayAndEmptyGroups() throws {
        let data = Data(#"{"proxies":{"Node":{"type":"VLESS","history":[{"delay":99},{"delay":12}]},"Provider":{"type":"URLTest","all":[]}}}"#.utf8)
        let result = try ProxySnapshot.decode(data)
        XCTAssertEqual(result.nodes["Node"]?.delay, 12)
        XCTAssertEqual(result.groups.first?.name, "Provider")
    }

    func testAutoGroupsPreserveFixedSelection() throws {
        let data = Data(#"{"proxies":{"Auto":{"type":"URLTest","all":["A","B"],"now":"A","fixed":"B"}}}"#.utf8)
        let result = try ProxySnapshot.decode(data)
        XCTAssertEqual(result.groups.first?.fixed, "B")
        XCTAssertTrue(result.groups.first?.confirmsSelection("B") == true)
    }

    func testMalformedResponseFailsInsteadOfPublishingAnEmptySnapshot() {
        XCTAssertThrowsError(try ProxySnapshot.decode(Data(#"{"message":"error"}"#.utf8)))
    }
}
