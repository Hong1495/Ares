import XCTest

final class MITMDomainMatcherTests: XCTestCase {
    func testNormalizedPatternsAcceptCommaChineseCommaAndNewline() {
        XCTAssertEqual(
            MITMDomainMatcher.normalizedPatterns(from: " Example.com,*.api.com， z.ai\nGLM.cn "),
            ["example.com", "*.api.com", "z.ai", "glm.cn"]
        )
    }

    func testHostMatchingSupportsExactSubdomainAndWildcardSuffix() {
        let patterns = ["example.com", "*.api.example.net"]

        XCTAssertTrue(MITMDomainMatcher.host("example.com", matches: patterns))
        XCTAssertTrue(MITMDomainMatcher.host("cdn.example.com", matches: patterns))
        XCTAssertTrue(MITMDomainMatcher.host("v1.api.example.net", matches: patterns))
        XCTAssertFalse(MITMDomainMatcher.host("badexample.com", matches: patterns))
    }

    func testBypassDomainsMatchSubdomains() {
        XCTAssertTrue(MITMDomainMatcher.host("securepubads.g.doubleclick.net", matches: MITMDomainMatcher.mitmBypassDomains))
        XCTAssertTrue(MITMDomainMatcher.host("a.securepubads.g.doubleclick.net", matches: MITMDomainMatcher.mitmBypassDomains))
        XCTAssertFalse(MITMDomainMatcher.host("doubleclick.net.example", matches: MITMDomainMatcher.mitmBypassDomains))
    }
}
