import XCTest

final class TopologySnapshotTests: XCTestCase {
    func testColumnDeduplicationAndFallbacks() {
        let a = TopologyRow(source: "Safari", rule: "Match", chain: ["node", "Auto"], host: "example.com", destinationIP: "1.2.3.4")
        let b = TopologyRow(source: "Mail", rule: "RuleSet", chain: ["DIRECT"], host: "", destinationIP: "1.2.3.4")
        let snapshot = TopologySnapshot(rows: [a, a, b])
        XCTAssertEqual(snapshot.processCount, 2)
        XCTAssertEqual(snapshot.ruleCount, 2)
        XCTAssertEqual(snapshot.proxyCount, 2)
        XCTAssertEqual(snapshot.targetCount, 2)
        XCTAssertEqual(a.proxy, "Auto")
        XCTAssertEqual(b.proxy, "DIRECT")
        XCTAssertEqual(b.target, "1.2.3.4")
        XCTAssertEqual(snapshot.subtitle, "Topology")
    }
    func testAllConnectionsAreRepresentedBeyondFormerLimit() {
        let rows = (0..<2500).map { TopologyRow(source: "App\($0)", rule: "Match", chain: [], host: "host\($0)", destinationIP: "") }
        let snapshot = TopologySnapshot(rows: rows)
        XCTAssertEqual(snapshot.rows.count, 2500)
        XCTAssertEqual(snapshot.processCount, 2500)
        XCTAssertEqual(snapshot.targetCount, 2500)
        XCTAssertEqual(snapshot.subtitle, "Topology")
        XCTAssertEqual(TopologySnapshot(rows: []).processCount, 0)
    }
}
