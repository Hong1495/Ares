import XCTest

final class ActivityFunctionsTests: XCTestCase {
    func connection(_ down: Int64 = 100, _ up: Int64 = 50) -> Connection {
        ConnectionSnapshot.decode(Data("""
        {"connections":[{"id":"a","metadata":{"process":"Browser","host":"example.com","destinationIP":"1.2.3.4"},"download":\(down),"upload":\(up),"chains":["Tokyo","Automatic"],"rule":"RuleSet"}]}
        """.utf8))[0]
    }
    func testSearchFindsChildHostAndPreservesParent() {
        var app = AppSession(id: "Browser", name: "Browser", iconPath: nil)
        app.activeConnections = [connection()]
        app.activeConnectionCount = 1
        XCTAssertEqual(ActivityPresentation.filter([.app(app)], query: "example.com").count, 1)
        XCTAssertEqual(ActivityPresentation.filter([.app(app)], query: "Tokyo").count, 1)
        XCTAssertTrue(ActivityPresentation.filter([.app(app)], query: "missing").isEmpty)
    }
    func testSortUsesBytesAndCSVQuotes() {
        XCTAssertEqual(ActivityNode.connection(connection()).sortValue, 100)
        XCTAssertEqual(ActivityNode.connection(connection()).uploadSortValue, 50)
        var conn = connection()
        let csv = ActivityPresentation.csv([conn])
        XCTAssertTrue(csv.contains("\"example.com\""))
        XCTAssertTrue(csv.contains("Process"))
        conn.metadata.process = "=bad\"name"
        XCTAssertTrue(ActivityPresentation.csv([conn]).contains("\"'=bad\"\"name\""))
    }
    func testGroupingAndExpandedConnectionSpeeds() async {
        let calculator = ConnectionsCalculator()
        var app = AppSession(id: "Browser", name: "Browser", iconPath: nil)
        app.activeConnections = [connection()]
        let start = Date()
        _ = await calculator.process(rawConnections: [connection()], appSessions: [app], groupingMode: .app, now: start)
        let next = await calculator.process(rawConnections: [connection(300, 150)], appSessions: [app], groupingMode: .app, now: start.addingTimeInterval(2))
        guard case .connection(let child) = next.nodes[0].children![0] else { return XCTFail() }
        XCTAssertEqual(child.downloadSpeed, 100)
        XCTAssertEqual(child.uploadSpeed, 50)
        let proxy = await calculator.regroup(connections: next.connections, sessions: [], mode: .proxy)
        XCTAssertEqual(proxy.first?.title, "Tokyo")
        let host = await calculator.regroup(connections: next.connections, sessions: [], mode: .host)
        XCTAssertEqual(host.first?.title, "example.com")
        let rule = await calculator.regroup(connections: next.connections, sessions: [], mode: .rule)
        XCTAssertEqual(rule.first?.title, "RuleSet")
        let rollback = await calculator.process(rawConnections: [connection(1, 1)], appSessions: [], groupingMode: .host, now: start.addingTimeInterval(3))
        XCTAssertEqual(rollback.connections[0].downloadSpeed, 0)
    }
    func testNoFirstSampleSpeedSpikeAndResetBaseline() async {
        let auditor = TrafficAuditor()
        let now = Date()
        let initial = await auditor.process(connections: [connection()], now: now)
        XCTAssertEqual(initial[0].currentDownloadSpeed, 0)
        XCTAssertEqual(initial[0].totalDownload, 100)
        let stale = await auditor.process(connections: [], now: now.addingTimeInterval(600))
        XCTAssertEqual(stale[0].totalDownload, 100)
        await auditor.reset()
        let afterReset = await auditor.process(connections: [connection(120, 60)], now: now.addingTimeInterval(601))
        XCTAssertEqual(afterReset[0].totalDownload, 20)
    }
}
