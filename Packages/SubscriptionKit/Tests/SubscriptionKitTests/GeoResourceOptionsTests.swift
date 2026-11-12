import XCTest
@testable import SubscriptionKit

final class GeoResourceOptionsTests: XCTestCase {
    func testCustomURLsAndNoOverrides() throws {
        XCTAssertEqual(try GeoResourceOptions.urls(in: "rules: [MATCH,DIRECT]"), [:])
        XCTAssertEqual(try GeoResourceOptions.urls(in: "geox-url: {mmdb: 'https://example.com/custom.mmdb', geosite: 'https://example.com/site.dat'}"),
                       ["mmdb": "https://example.com/custom.mmdb", "geosite": "https://example.com/site.dat"])
    }
    func testMalformedDocumentFails() {
        XCTAssertThrowsError(try GeoResourceOptions.urls(in: "[invalid"))
    }
}
