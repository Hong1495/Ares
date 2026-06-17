import XCTest

final class CoreReleaseSelectorTests: XCTestCase {
    func testParseDisplayVersionPrefersVersionToken() {
        let raw = "Mihomo Meta v1.19.18 darwin arm64 with go1.25.5"
        XCTAssertEqual(CoreReleaseSelector.parseDisplayVersion(from: raw), "v1.19.18")
    }

    func testParseDisplayVersionFallsBackToFirstLine() {
        XCTAssertEqual(CoreReleaseSelector.parseDisplayVersion(from: "hello\nworld"), "hello")
    }

    func testVersionComparison() {
        XCTAssertTrue(CoreReleaseSelector.isUpdateAvailable(current: "v1.19.18", latest: "v1.19.27"))
        XCTAssertFalse(CoreReleaseSelector.isUpdateAvailable(current: "v1.19.27", latest: "v1.19.18"))
    }

    func testAssetSelectionPrefersDefaultDarwinArm64Asset() {
        guard let urlA = URL(string: "https://example.com/a"),
              let urlB = URL(string: "https://example.com/b") else {
            XCTFail("Test URLs should be valid")
            return
        }

        let asset = CoreReleaseSelector.selectDarwinARM64Asset(from: [
            (name: "mihomo-darwin-arm64-go120-v1.19.27.gz", url: urlA),
            (name: "mihomo-darwin-arm64-v1.19.27.gz", url: urlB)
        ])

        XCTAssertEqual(asset?.name, "mihomo-darwin-arm64-v1.19.27.gz")
    }
}
