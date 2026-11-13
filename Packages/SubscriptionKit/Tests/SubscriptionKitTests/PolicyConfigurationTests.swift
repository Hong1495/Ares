import XCTest
@testable import SubscriptionKit

final class PolicyConfigurationTests: XCTestCase {
    let source = """
    proxy-groups:
      - name: Auto
        type: url-test
        proxies: [DIRECT]
        interval: 600
        tolerance: 80
        lazy: true
        url: https://example.test/check
        custom-field: preserved
      - {name: Balance, type: load-balance, use: [Remote], strategy: consistent-hashing}
    proxy-providers:
      Remote: {type: http, url: 'https://example.test/secret-token', interval: 7200}
    """
    func testOverridesAndRestoredInheritancePreserveOtherFields() throws {
        let edited = try PolicyConfiguration.apply(source: source, overrides: #"{"Auto":{"interval":"120","lazy":"false"},"Balance":{"strategy":"round-robin"}}"#)
        let groups = try PolicyConfiguration.read(edited)
        XCTAssertEqual(groups[0].fields["interval"], "120")
        XCTAssertEqual(groups[0].fields["tolerance"], "80")
        XCTAssertEqual(groups[0].fields["lazy"], "false")
        XCTAssertEqual(groups[1].fields["strategy"], "round-robin")
        XCTAssertTrue(edited.contains("custom-field: preserved"))
        XCTAssertTrue(edited.contains("7200"))
        XCTAssertEqual(try PolicyConfiguration.read(PolicyConfiguration.apply(source: source, overrides: "{}"))[0].fields["interval"], "600")
    }
    func testInvalidOrWrongGroupParametersFail() {
        for overrides in [#"{"Auto":{"timeout":"0"}}"#, #"{"Auto":{"interval":"-1"}}"#, #"{"Auto":{"strategy":"round-robin"}}"#, #"{"Auto":{"lazy":"yes"}}"#, #"{"Balance":{"strategy":"fake"}}"#, #"{"Auto":{"url":"secret"}}"#] {
            XCTAssertThrowsError(try PolicyConfiguration.apply(source: source, overrides: overrides))
        }
    }
    func testMissingGroupDoesNotCreateItAndMetadataDoesNotExposeSecrets() throws {
        XCTAssertThrowsError(try PolicyConfiguration.apply(source: source, overrides: #"{"Removed":{"interval":"10"}}"#))
        XCTAssertThrowsError(try PolicyConfiguration.apply(source: "{}", overrides: #"{"Removed":{"interval":"10"}}"#))
        let groups = try PolicyConfiguration.read(source)
        XCTAssertEqual(groups.count, 2)
        XCTAssertNil(groups[0].fields["url"])
        XCTAssertNil(groups[0].fields["custom-field"])
        XCTAssertEqual(groups[1].providers, ["Remote"])
    }
    func testExplicitEmptyFilterRemainsAString() throws {
        let result = try PolicyConfiguration.apply(source: source, overrides: #"{"Auto":{"filter":""}}"#)
        XCTAssertEqual(try PolicyConfiguration.read(result)[0].fields["filter"], "")
        XCTAssertTrue(result.contains("filter: \"\""))
    }
    func testStableOverrideSerialization() throws {
        let values = ["Auto": ["filter": "HK|JP", "interval": "300"]]
        XCTAssertEqual(try PolicyConfiguration.decodeOverrides(PolicyConfiguration.encodeOverrides(values)), values)
    }
}
