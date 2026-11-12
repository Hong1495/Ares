import XCTest

final class IPReputationTests: XCTestCase {
    func testValidScoreAndTypes() {
        let data = Data(#"{"status":"ok","8.8.8.8":{"detections":{"risk":33,"hosting":true,"vpn":false}}}"#.utf8)
        let date = Date(timeIntervalSince1970: 100)
        let value = IPReputation.parse(data, status: 200, ip: "8.8.8.8", now: date)
        XCTAssertEqual(value?.risk, 33)
        XCTAssertEqual(value?.types, ["Hosting"])
        XCTAssertEqual(value?.checkedAt, date)
        XCTAssertNil(IPReputation.parse(data, status: 429, ip: "8.8.8.8"))
        XCTAssertNil(IPReputation.parse(data, status: 200, ip: "1.1.1.1"))
    }

    func testInvalidAndMissingScoresNeverBecomeClean() {
        for score in ["null", "true", "-1", "101", "0.5", "\"0\""] {
            let data = Data("{\"status\":\"ok\",\"8.8.8.8\":{\"detections\":{\"risk\":\(score)}}}".utf8)
            XCTAssertNil(IPReputation.parse(data, status: 200, ip: "8.8.8.8"), score)
        }
        XCTAssertNil(IPReputation.parse(Data(#"{"status":"denied"}"#.utf8), status: 200, ip: "8.8.8.8"))
    }
}
