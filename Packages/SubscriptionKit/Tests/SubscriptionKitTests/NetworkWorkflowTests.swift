import XCTest
@testable import SubscriptionKit

final class NetworkWorkflowTests: XCTestCase {
    private let source = """
    proxies:
      - {name: One, type: http, server: 127.0.0.1, port: 8080}
      - {name: Two, type: http, server: 127.0.0.1, port: 8081}
    proxy-groups:
      - {name: Ares Auto, type: select, proxies: [One]}
    rules: ['MATCH,Ares Auto']
    """
    func testRecommendedPoliciesAreAdditiveAndCollisionSafe() throws {
        let plan = try RecommendedPolicies.make(source: source, overrides: "{}")
        XCTAssertEqual(plan.automatic, "Ares Auto 2")
        let rendered = try PolicyConfiguration.apply(source: source, overrides: plan.overrides)
        let groups = try PolicyConfiguration.read(rendered)
        XCTAssertEqual(groups.count, 4)
        XCTAssertEqual(groups.first { $0.name == "Ares Auto" }?.members, ["One"])
        XCTAssertEqual(groups.first { $0.name == plan.fallback }?.members, ["One", "Two"])
        XCTAssertEqual(groups.first { $0.name == plan.automatic }?.fields["tolerance"], "50")
        XCTAssertEqual(groups.first { $0.name == plan.automatic }?.fields["lazy"], "false")
        XCTAssertTrue(rendered.contains("MATCH"))
        let next = try RecommendedPolicies.make(source: source, overrides: plan.overrides)
        XCTAssertNotEqual(next.manual, plan.manual)
        XCTAssertThrowsError(try RecommendedPolicies.make(source: "{}", overrides: "{}"))
        let resource = try RecommendedPolicies.make(source: "proxy-providers: {Remote: {type: file, path: nodes.yaml}}", overrides: "{}")
        let fields = try PolicyConfiguration.decodeOverrides(resource.overrides)
        XCTAssertEqual(try PolicyConfiguration.list(fields[resource.fallback]!["use"]!), ["Remote"])
    }
    func testApplicationRulesPreserveUnrelatedRulesAndRemoveAllExactDuplicates() throws {
        let path = "/Applications/Fixture.app/Contents/MacOS/Fixture"
        let rules = "# Keep\nPROCESS-PATH,\(path),Old\nDOMAIN,example.test,DIRECT\nPROCESS-PATH,\(path),Other\nPROCESS-NAME,Fixture,DIRECT\nMATCH,Proxy\n"
        let result = try ApplicationRouting.replacing(rules, paths: [path, path], target: "New")
        XCTAssertTrue(result.hasPrefix("PROCESS-PATH,\(path),New\n# Keep"))
        XCTAssertEqual(ApplicationRouting.paths(in: result), [path])
        XCTAssertFalse(result.contains(",Old")); XCTAssertFalse(result.contains(",Other"))
        XCTAssertTrue(result.contains("PROCESS-NAME,Fixture,DIRECT"))
        let removed = try ApplicationRouting.replacing(result, paths: [path], target: nil)
        XCTAssertTrue(ApplicationRouting.paths(in: removed).isEmpty)
        XCTAssertTrue(removed.hasSuffix("MATCH,Proxy\n"))
        for invalid in ["Unknown", "/Applications/Fixture.app", "/tmp/x,y", "/tmp/x\nMATCH,REJECT", "/tmp/x\r"] {
            XCTAssertFalse(ApplicationRouting.validPath(invalid))
            XCTAssertThrowsError(try ApplicationRouting.replacing(rules, paths: [invalid], target: "DIRECT"))
        }
        XCTAssertThrowsError(try ApplicationRouting.replacing(rules, paths: [path], target: "a\nMATCH,DIRECT"))
    }
    func testPrecedenceEvidenceDoesNotPretendToEvaluateAdvancedRules() throws {
        let rules = ["DOMAIN,a.test,DIRECT", "RULE-SET,Applications,Proxy", "PROCESS-NAME,App,Proxy", "PROCESS-PATH,/bin/App,REJECT", "MATCH,DIRECT"]
        let evidence = ApplicationRouting.evidence(paths: ["/bin/App"], rules: rules)
        XCTAssertEqual(evidence.map(\.order), [2, 3, 4, 5])
        XCTAssertTrue(evidence[0].explanation.contains("evaluated by the core"))
        XCTAssertEqual(try ApplicationRouting.configuredRules("rules: ['MATCH,DIRECT']"), ["MATCH,DIRECT"])
    }
    func testQualityStatisticsUseMeasuredSamplesAndBreakVariationAtFailures() {
        let samples: [NetworkQuality.Sample] = [.init(milliseconds: 100, outcome: "ok"), .init(milliseconds: 200, outcome: "ok"), .init(milliseconds: nil, outcome: "failure"), .init(milliseconds: 900, outcome: "ok")]
        let stats = NetworkQuality.Summary(samples)
        XCTAssertEqual(stats.attempts, 4); XCTAssertEqual(stats.successes, 3)
        XCTAssertEqual(stats.successPercent, 75); XCTAssertEqual(stats.median, 200)
        XCTAssertEqual(stats.p95, 900); XCTAssertEqual(stats.variation, 100)
        XCTAssertNil(NetworkQuality.Summary([]).successPercent)
        XCTAssertNil(NetworkQuality.Summary([.init(milliseconds: nil, outcome: "failed")]).p95)
    }
    func testQualityWindowRetentionAndObservedSwitchAttribution() {
        var window = NetworkQuality.Window()
        for value in 1...130 { window.record(.init(milliseconds: value, outcome: "ok"), target: "test") }
        XCTAssertEqual(window.samples["test"]?.count, 120)
        window.recordUnavailable(target: "test"); XCTAssertEqual(window.unavailable["test"], 1)
        window.observe(.init(path: ["Auto", "One"], pinned: false, kind: "URLTest"))
        XCTAssertTrue(window.events.isEmpty)
        window.observe(.init(path: ["Auto", "Two"], pinned: false, kind: "URLTest"))
        XCTAssertTrue(window.events[0].reason.contains("trigger not exposed"))
        window.observe(.init(path: ["Auto", "One"], pinned: true, kind: "URLTest"))
        XCTAssertEqual(window.events[0].reason, "Manual selection observed")
        window.observe(.init(path: ["Auto", "One"], pinned: false, kind: "URLTest"))
        XCTAssertEqual(window.events[0].reason, "Automatic selection resumed")
        for index in 0...110 { window.observe(.init(path: ["Auto", String(index)], pinned: false, kind: "Fallback")) }
        XCTAssertEqual(window.events.count, 100)
    }
}
