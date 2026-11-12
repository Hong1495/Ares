import XCTest

final class ActivityTrafficLedgerTests: XCTestCase {
    private func connection(_ down: Int64, _ up: Int64) -> [Connection] {
        ConnectionSnapshot.decode(Data("{\"connections\":[{\"id\":\"a\",\"metadata\":{},\"download\":\(down),\"upload\":\(up)}]}".utf8))
    }
    func testTotalsSurviveClosedRowsAndMissingSnapshots() {
        var ledger = ActivityTrafficLedger()
        ledger.record(connection(100, 50))
        ledger.record([])
        XCTAssertEqual(ledger.download, 100)
        ledger.record(connection(120, 70))
        XCTAssertEqual(ledger.download, 120)
        XCTAssertEqual(ledger.upload, 70)
    }
    func testResetPreservesOpenConnectionBaseline() {
        var ledger = ActivityTrafficLedger()
        ledger.record(connection(100, 50))
        ledger.reset()
        ledger.record(connection(120, 70))
        XCTAssertEqual(ledger.download, 20)
        XCTAssertEqual(ledger.upload, 20)
    }
}
