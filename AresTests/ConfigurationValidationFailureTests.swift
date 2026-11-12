import XCTest

final class ConfigurationValidationFailureTests: XCTestCase {
    func testResourceIdentification() {
        XCTAssertEqual(ConfigurationValidationFailure.resourceKey(in: "can't download MMDB: DNS failed"), "mmdb")
        XCTAssertEqual(ConfigurationValidationFailure.resourceKey(in: "can't download GeoSite.dat"), "geosite")
        XCTAssertEqual(ConfigurationValidationFailure.resourceKey(in: "can't download GeoIP.dat"), "geoip")
        XCTAssertEqual(ConfigurationValidationFailure.resourceKey(in: "can't download ASN.mmdb"), "asn")
        XCTAssertNil(ConfigurationValidationFailure.resourceKey(in: "invalid proxy type"))
        XCTAssertEqual(ConfigurationValidationFailure.resourceKey(in: "Can't find MMDB, start download"), "mmdb")
        XCTAssertNil(ConfigurationValidationFailure.resourceKey(in: "Can't find MMDB, start download\nDownload MMDB finish\ninvalid rule"))
    }
    func testGeoResourceFailureIsNotInvalidSubscription() {
        XCTAssertTrue(ConfigurationValidationFailure.isResourceFailure("rules[511] [GEOIP,CN,DIRECT] error: can't download MMDB: dns resolve failed"))
        XCTAssertFalse(ConfigurationValidationFailure.isResourceFailure("proxy 2: unsupported proxy type"))
        XCTAssertFalse(ConfigurationValidationFailure.isResourceFailure("yaml: mapping values are not allowed in this context"))
        XCTAssertFalse(ConfigurationValidationFailure.isResourceFailure("connection refused"))
    }
}
