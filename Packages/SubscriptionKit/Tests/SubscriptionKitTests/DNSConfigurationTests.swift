import XCTest
import Yams
@testable import SubscriptionKit

final class DNSConfigurationTests: XCTestCase {
    let source = """
    dns:
      enable: true
      nameserver: [1.1.1.1]
      nameserver-policy: {'+.private.test': [192.0.2.53]}
      enhanced-mode: redir-host
      future-option: preserved
    hosts: {old.test: 192.0.2.10}
    proxies: []
    rules: [MATCH,DIRECT]
    """
    func testReplacementAndInheritancePreserveUnownedFields() throws {
        let overrides = ["nameserver-policy": "'+.new.test': [192.0.2.54]", "hosts": "new.test: 192.0.2.11", "respect-rules": "true"]
        let text = try DNSConfiguration.apply(source: source, overrides: DNSConfiguration.encode(overrides))
        let node = try Yams.compose(yaml: text)!
        XCTAssertEqual(node["dns"]?["enable"]?.bool, true)
        XCTAssertEqual(node["dns"]?["future-option"]?.string, "preserved")
        XCTAssertEqual(node["dns"]?["nameserver"]?.sequence?.first?.string, "1.1.1.1")
        XCTAssertNil(node["dns"]?["nameserver-policy"]?["+.private.test"])
        XCTAssertNil(node["hosts"]?["old.test"])
        XCTAssertEqual(node["hosts"]?["new.test"]?.string, "192.0.2.11")
        XCTAssertEqual(try DNSConfiguration.apply(source: source, overrides: "{}"), source)
    }
    func testAllSupportedFieldsValidate() throws {
        for field in DNSConfiguration.fields { try DNSConfiguration.validate(key: field.key, value: field.example) }
        try DNSConfiguration.validate(key: "fake-ip-filter", value: "[]")
        try DNSConfiguration.validate(key: "nameserver-policy", value: "{}")
    }
    func testInvalidShapeDuplicateAndOwnedFieldsRejected() {
        for (key, value) in [("enable", "false"), ("listen", "0.0.0.0:53"), ("nameserver", "[1.1.1.1]"),
            ("nameserver-policy", "[]"), ("hosts", "same: 1\nsame: 2"), ("fallback", "{key: value}"),
            ("fallback", "- {x: y}"), ("respect-rules", "wrong"), ("respect-rules", "\"true\""), ("fallback", "[123]"), ("enhanced-mode", "other"),
            ("fake-ip-filter-mode", "other"), ("hosts", ""), ("hosts", "foo: [unterminated") ] {
            XCTAssertThrowsError(try DNSConfiguration.validate(key: key, value: value), key)
        }
    }
    func testAdvancedOverlayDoesNotSuppressAppDefaults() throws {
        let baseline = try EffectiveConfiguration.build(source: "proxies: []", defaults: "dns: {enable: true, nameserver: [1.1.1.1], enhanced-mode: fake-ip}", overrides: [])
        let text = try DNSConfiguration.apply(source: baseline, overrides: #"{"hosts":"sample.test: 192.0.2.1","respect-rules":"false"}"#)
        let node = try Yams.compose(yaml: text)
        XCTAssertEqual(node?["dns"]?["enable"]?.bool, true)
        XCTAssertEqual(node?["dns"]?["nameserver"]?.sequence?.count, 1)
        XCTAssertEqual(try DNSConfiguration.read(baseline)["enhanced-mode"], "fake-ip")
    }
    func testRoundTripAndInvalidStorage() throws {
        let values = ["hosts": "a.test: 192.0.2.1\nb.test: 192.0.2.2"]
        XCTAssertEqual(try DNSConfiguration.decode(DNSConfiguration.encode(values)), values)
        XCTAssertThrowsError(try DNSConfiguration.decode("[]"))
        XCTAssertThrowsError(try DNSConfiguration.decode(#"{"hosts":true}"#))
    }
}
