import XCTest

final class ProxyFlagTests: XCTestCase {
    func testRegionalIndicatorsDecodeWithoutRelyingOnFontOrLocale() {
        XCTAssertEqual(ProxyFlag.regionCode(for: "🇹🇼"), "TW")
        XCTAssertEqual(ProxyFlag.regionCode(for: "🇺🇸"), "US")
        XCTAssertEqual(ProxyFlag.regionCode(for: "🇪🇺"), "EU")
        XCTAssertNil(ProxyFlag.regionCode(for: "🇹"))
    }

    func testInlineFlagsPreserveOrderWhitespaceAndOtherEmoji() {
        let name = "🇹🇼 台湾🚀 🇺🇸 / 🇯🇵 01"
        XCTAssertEqual(ProxyFlag.segments(in: name), [
            .flag("TW"), .text(" 台湾🚀 "), .flag("US"), .text(" / "), .flag("JP"), .text(" 01")
        ])
        XCTAssertEqual(ProxyFlag.plainName(name), "[TW] 台湾🚀 [US] / [JP] 01")
        XCTAssertEqual(ProxyFlag.segments(in: "节点 🏳️‍🌈 🚀"), [.text("节点 🏳️‍🌈 🚀")])
        XCTAssertEqual(ProxyFlag.segments(in: ""), [])
    }

    func testSubdivisionFlagsAndUnknownCodesHaveReadableNames() {
        let scotland = "\u{1F3F4}\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F}"
        XCTAssertEqual(ProxyFlag.segments(in: scotland + " Glasgow"), [.flag("GB-SCT"), .text(" Glasgow")])
        XCTAssertEqual(ProxyFlag.plainName("🇿🇿 Example"), "[ZZ] Example")
    }
}
