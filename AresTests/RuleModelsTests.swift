import XCTest

final class RuleModelsTests: XCTestCase {
    func testActualCountersOrderAndAbsentStatistics() throws {
        let data = Data(#"{"rules":[{"index":1,"type":"Match","payload":"","proxy":"DIRECT"},{"index":0,"type":"DomainSuffix","payload":"example.test","proxy":"Proxy","extra":{"disabled":false,"hitCount":42}}]}"#.utf8)
        let rules = try ClashRule.decode(data)
        XCTAssertEqual(rules.map(\.index), [0, 1])
        XCTAssertEqual(rules[0].hit, 42)
        XCTAssertNil(rules[1].hit)
    }
    func testInvalidOrDuplicateRulesAreRejectedWithoutPartialResults() {
        for body in [#"{"rules":[{"index":0,"type":"Match","payload":"","proxy":"DIRECT"},{"index":0,"type":"Match","payload":"","proxy":"DIRECT"}]}"#,
                     #"{"rules":[{"index":0,"type":"Match"}]}"#,
                     #"{"error":"unavailable"}"#] {
            XCTAssertThrowsError(try ClashRule.decode(Data(body.utf8)))
        }
    }
    func testProviderMetadataAndInlineUpdatePolicy() throws {
        let body = #"{"providers":{"Local":{"name":"Local","behavior":"classical","vehicleType":"Inline","ruleCount":0,"updatedAt":"0001-01-01T00:00:00Z"},"Remote":{"name":"Remote","behavior":"domain","vehicleType":"HTTP","ruleCount":50,"updatedAt":"2026-11-13T01:02:03.123456+08:00"}}}"#
        let values = try RuleProvider.decode(Data(body.utf8))
        XCTAssertEqual(values.count, 2)
        XCTAssertFalse(values[0].canUpdate)
        XCTAssertNil(values[0].updatedDate)
        XCTAssertTrue(values[1].canUpdate)
        XCTAssertNotNil(values[1].updatedDate)
    }
    func testProviderIdentityMismatchFails() {
        let body = #"{"providers":{"Other":{"name":"Local","behavior":"domain","vehicleType":"HTTP","ruleCount":0}}}"#
        XCTAssertThrowsError(try RuleProvider.decode(Data(body.utf8)))
    }
}
