import XCTest
@testable import SubscriptionKit

final class RuleEditingTests: XCTestCase {
    func testRoundTripPreservesCommentsBlankLinesAndAdvancedRules() {
        let source = "# note\n  - DOMAIN-SUFFIX,example.test,DIRECT\n\nAND,((NETWORK,tcp),(DST-PORT,443)),Proxy\n"
        var draft = RuleDraftDocument(source)
        XCTAssertEqual(draft.text, source)
        let first = draft.rules[0].id
        draft.replace(id: first, with: "DOMAIN-SUFFIX,new.test,DIRECT")
        XCTAssertEqual(draft.text, source.replacingOccurrences(of: "example.test", with: "new.test"))
        draft.move(id: first, by: 1)
        XCTAssertTrue(draft.rules[0].rule!.hasPrefix("AND,"))
        XCTAssertTrue(draft.text.contains("# note"))
        XCTAssertTrue(draft.text.hasSuffix("\n"))
        draft.move(id: first, by: 1) // Last row cannot move past end.
        XCTAssertEqual(draft.rules.count, 2)
        draft.remove(id: first)
        draft.append("MATCH,DIRECT")
        XCTAssertEqual(draft.rules.map(\.rule), ["AND,((NETWORK,tcp),(DST-PORT,443)),Proxy", "MATCH,DIRECT"])
    }
    func testFormRoundTripsOnlySupportedSyntax() {
        for raw in ["DOMAIN-SUFFIX,example.test,Proxy", "MATCH,DIRECT", "IP-CIDR,10.0.0.0/8,DIRECT,no-resolve"] {
            XCTAssertEqual(RuleForm(raw)?.serialized, raw)
        }
        for raw in ["AND,((NETWORK,tcp),(DST-PORT,443)),Proxy", "DOMAIN-REGEX,a{1,3},Proxy",
                    "RULE-SET,Private,Proxy,src", "DOMAIN,example.test,DIRECT,no-resolve", "DOMAIN,example.test,DIRECT,unknown"] {
            XCTAssertNil(RuleForm(raw), raw)
        }
    }
    func testFormRejectsEmptyAndInjectedFields() {
        XCTAssertNotNil(RuleForm(payload: "").validationError)
        XCTAssertNotNil(RuleForm(payload: "x", target: "\nMATCH,DIRECT").validationError)
        XCTAssertNotNil(RuleForm(type: "NETWORK", payload: "invalid").validationError)
        XCTAssertNil(RuleForm(type: "MATCH").validationError)
    }
    func testSourcesPreserveOrderDuplicatesAndAllSubRules() throws {
        let source = """
        rules:
          - AND,((RULE-SET,One),(NOT,((RULE-SET,Two)))),Proxy
          - SUB-RULE,(NETWORK,tcp),Nested
          - MATCH,DIRECT
        sub-rules:
          Nested:
            - RULE-SET,One,Proxy
            - MATCH,DIRECT
          Unused:
            - RULE-SET,Two,Proxy
        rule-providers:
          One: {type: inline, behavior: domain, payload: [example.test]}
          Two: {type: http, url: 'https://secret.invalid/token', path: ./two.yaml}
        """
        let local = "# comment\nDOMAIN,local.test,DIRECT\nDOMAIN,local.test,DIRECT"
        let effective = try EffectiveConfiguration.build(source: source, defaults: "{}", overrides: [], rules: RuleDraftDocument(local).rules.compactMap(\.rule))
        let result = try RuleSourceDocument.read(configuration: effective, subscription: source, localRules: local)
        XCTAssertEqual(result.rows.count, 8)
        XCTAssertEqual(result.rows.prefix(2).map(\.origin), ["Local override", "Local override"])
        XCTAssertEqual(result.rows[2].origin, "Subscription")
        XCTAssertEqual(result.rows[2].providers, ["One", "Two"])
        XCTAssertEqual(result.rows[3].subRules, ["Nested"])
        XCTAssertEqual(result.references(to: "One").count, 2)
        XCTAssertEqual(result.references(to: "Two").count, 2)
        XCTAssertEqual(result.providerNames, ["One", "Two"])
        XCTAssertFalse(result.rows.contains { $0.rule.contains("secret.invalid") })
        XCTAssertTrue(result.issues.isEmpty, result.issues.joined(separator: "\n"))
    }
    func testChangedSourceDoesNotInventProvenance() throws {
        let result = try RuleSourceDocument.read(configuration: "rules: ['MATCH,DIRECT']", subscription: "rules: ['MATCH,REJECT']", localRules: "DOMAIN,test,DIRECT")
        XCTAssertEqual(result.rows.first?.origin, "Verified configuration")
    }
    func testUnknownOrMalformedExpressionsAreNotSilentlyAccepted() throws {
        let result = try RuleSourceDocument.read(configuration: "rules: ['AND,((RULE-SET,A),Proxy']", subscription: nil, localRules: nil)
        XCTAssertEqual(result.issues.count, 1)
        XCTAssertThrowsError(try RuleSourceDocument.read(configuration: "rules: [1, {a: b}]", subscription: nil, localRules: nil))
    }
}
