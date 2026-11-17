import XCTest
@testable import SubscriptionKit

final class ApplicationRoutingStatusTests: XCTestCase {
    private let main = "/Applications/Browser.app/Contents/MacOS/Browser"
    private let helper = "/Applications/Browser.app/Contents/Helpers/Network"
    private let saved = Date(timeIntervalSince1970: 100)
    private var rules: String { "PROCESS-PATH,\(main),Auto\nPROCESS-PATH,\(helper),DIRECT\nMATCH,Default" }

    func testSelectionReflectsSavedOverridesAndUnconfiguredHelpers() {
        XCTAssertEqual(ApplicationRouting.selectionRoute(paths: [main], rules: rules), .target("Auto"))
        XCTAssertEqual(ApplicationRouting.selectionRoute(paths: [helper], rules: rules), .target("DIRECT"))
        XCTAssertEqual(ApplicationRouting.selectionRoute(paths: [main, helper], rules: rules), .mixed)
        XCTAssertEqual(ApplicationRouting.selectionRoute(paths: ["/bin/other"], rules: rules), .inherited)
        XCTAssertEqual(ApplicationRouting.selectionRoute(paths: [main, "/bin/other"], rules: rules), .mixed)
        XCTAssertEqual(ApplicationRouting.selectionRoute(paths: [], rules: rules), .inherited)
    }

    func testDuplicateRulesExposeFirstMatchAndConflict() {
        let duplicated = rules + "\nPROCESS-PATH,\(main),REJECT"
        XCTAssertEqual(ApplicationRouting.localRoutes(in: duplicated)[main]?.target, "Auto")
        XCTAssertEqual(ApplicationRouting.localRoutes(in: duplicated)[main]?.entries, 2)
        XCTAssertEqual(status(duplicated, []), .conflict)
    }

    func testVerificationRequiresExactRulePayloadAndRoute() {
        XCTAssertEqual(status(rules, [observation(main, target: "Auto")]), .verified)
        XCTAssertEqual(status(rules, [observation(main, target: "Other")]), .different)
        XCTAssertEqual(status(rules, [observation(main, target: "Auto", rule: "Match")]), .different)
        XCTAssertEqual(status(rules, [observation(main, target: "Auto", payload: helper)]), .different)
        XCTAssertEqual(status(rules, [observation(helper, target: "Auto")]), .pending)
        XCTAssertEqual(status(rules, []), .pending)
    }

    func testOldConnectionsCannotVerifyNewConfigurationAndBlockIsNotAssumed() {
        let old = observation(main, target: "Auto", at: saved.addingTimeInterval(-1))
        XCTAssertEqual(status(rules, [old]), .pending)
        let blocked = "PROCESS-PATH,\(main),REJECT"
        XCTAssertEqual(status(blocked, []), .pending)
        XCTAssertEqual(status(blocked, [observation(main, target: "REJECT")]), .verified)
    }

    func testAllExecutablesMustHaveEvidenceAndPartialCoverageStaysVisible() {
        let first = observation(main, target: "Auto")
        let second = observation(helper, target: "DIRECT")
        XCTAssertEqual(status(rules, [first], paths: [main, helper]), .partial)
        XCTAssertEqual(status(rules, [first, second], paths: [main, helper]), .verified)
        XCTAssertEqual(status("PROCESS-PATH,\(main),Auto", [first], paths: [main, helper]), .partial)
        XCTAssertEqual(ApplicationRouting.verification(paths: [main], rules: rules, observations: [first], available: false, ruleMode: true), .unavailable)
        XCTAssertEqual(ApplicationRouting.verification(paths: [main], rules: rules, observations: [first], available: true, ruleMode: false), .inactive)
        XCTAssertEqual(status("MATCH,Default", [first]), .inherited)
    }

    private func status(_ rules: String, _ observations: [ApplicationRouting.Observation], paths: [String]? = nil) -> ApplicationRouting.Verification {
        ApplicationRouting.verification(paths: paths ?? [main], rules: rules, observations: observations,
            available: true, ruleMode: true, notBefore: [main: saved, helper: saved])
    }
    private func observation(_ path: String, target: String, rule: String = "ProcessPath", payload: String? = nil, at: Date? = nil) -> ApplicationRouting.Observation {
        .init(path: path, startedAt: at ?? saved.addingTimeInterval(1), rule: rule, payload: payload ?? path, chain: ["Leaf", target])
    }
}
