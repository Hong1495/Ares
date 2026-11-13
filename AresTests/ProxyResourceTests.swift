import XCTest

final class ProxyResourceTests: XCTestCase {
    func testMissingMeasurementIsNotFailureOrZero() throws {
        let body = #"{"providers":{"A":{"name":"A","vehicleType":"HTTP","proxies":[{"name":"node","type":"VLESS"}]}}}"#
        let resource = try ProxyResource.decode(Data(body.utf8))[0]
        XCTAssertTrue(resource.canUpdate)
        XCTAssertNil(resource.proxies[0].latest)
        XCTAssertNil(resource.updatedDate)
    }
    func testInlineAndCompatibleResourcesCannotDownload() throws {
        for type in ["Inline", "Compatible"] {
            let data = try JSONSerialization.data(withJSONObject: ["providers": ["A": ["name": "A", "vehicleType": type, "proxies": []] as [String: Any]]])
            XCTAssertFalse(try ProxyResource.decode(data)[0].canUpdate)
        }
    }
    func testBadIdentityFails() {
        XCTAssertThrowsError(try ProxyResource.decode(Data(#"{"providers":{"A":{"name":"B","vehicleType":"HTTP","proxies":[]}}}"#.utf8)))
    }
    func testGraphReportsCyclesAndMissingMembersWithoutInventingBalanceExit() {
        let groups = [ProxyGroup(name: "A", type: "Selector", now: "B", all: ["B", "Missing"]),
                      ProxyGroup(name: "B", type: "LoadBalance", now: "A", all: ["A", "DIRECT"])]
        let graph = PolicyGraph.inspect(groups: groups, nodes: [:])
        XCTAssertEqual(graph.edges.count, 4)
        XCTAssertEqual(graph.issues.count, 2)
        XCTAssertTrue(graph.edges.first!.active)
        XCTAssertFalse(graph.edges.filter { $0.parent == "B" }.contains { $0.active })
    }
    func testLargeGraphDoesNotTruncate() {
        let groups = (0..<1000).map { ProxyGroup(name: "G\($0)", type: "Selector", all: $0 == 999 ? ["DIRECT"] : ["G\($0 + 1)"]) }
        let graph = PolicyGraph.inspect(groups: groups, nodes: [:])
        XCTAssertEqual(graph.edges.count, 1000)
        XCTAssertTrue(graph.issues.isEmpty)
    }
}
