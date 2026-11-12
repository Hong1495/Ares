import XCTest

final class ExitIdentityTests: XCTestCase {
    func testCountryAndIPComeFromSameValidResponse() {
        let data = Data(#"{"ip":"8.8.8.8","country":"United States","country_iso":"US"}"#.utf8)
        XCTAssertEqual(ExitIdentity.parse(data, status: 200), ExitIdentity(ip:"8.8.8.8",country:"US"))
        XCTAssertNil(ExitIdentity.parse(data, status: 429))
        XCTAssertNil(ExitIdentity.parse(Data(#"{"ip":"Offline","country":"US"}"#.utf8),status:200))
    }
    func testTraceIPv6AndMissingCountry() {
        XCTAssertEqual(ExitIdentity.parse(Data("ip=2001:4860::8888\nloc=JP\n".utf8),status:200), ExitIdentity(ip:"2001:4860::8888",country:"JP"))
        XCTAssertEqual(ExitIdentity.parse(Data(#"{"ip":"1.1.1.1"}"#.utf8),status:200)?.country,nil)
        XCTAssertNil(ExitIdentity.parse(Data("<html>Error</html>".utf8),status:200))
        for value in ["Offline","Fetching...","—", "", "999.1.1.1"] { XCTAssertFalse(ExitIdentity.isAddress(value)) }
    }
}
