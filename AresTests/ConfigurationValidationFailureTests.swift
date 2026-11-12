import XCTest

final class ConfigurationValidationFailureTests: XCTestCase {
    func testGeoResourceFailureIsNotInvalidSubscription() {
        XCTAssertTrue(ConfigurationValidationFailure.isResourceFailure("rules[511] [GEOIP,CN,DIRECT] error: can't download MMDB: dns resolve failed"))
        XCTAssertFalse(ConfigurationValidationFailure.isResourceFailure("proxy 2: unsupported proxy type"))
        XCTAssertFalse(ConfigurationValidationFailure.isResourceFailure("yaml: mapping values are not allowed in this context"))
        XCTAssertFalse(ConfigurationValidationFailure.isResourceFailure("connection refused"))
    }
}
