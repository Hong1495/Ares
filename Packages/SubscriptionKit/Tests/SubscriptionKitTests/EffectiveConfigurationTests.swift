import XCTest
import Yams
@testable import SubscriptionKit

final class EffectiveConfigurationTests: XCTestCase {
    private let base = """
    mixed-port: 17890
    external-controller: 127.0.0.1:19090
    secret: ""
    find-process-mode: always
    tun: {enable: true, stack: system, mtu: 1400, auto-route: true, dns-hijack: ["any:53"]}
    profile: {store-selected: true, store-fake-ip: true}
    dns:
      enable: true
      enhanced-mode: fake-ip
      nameserver: [223.5.5.5]
      fallback: [1.1.1.1]
    sniffer: {enable: true}
    """

    private func build(_ source: String, overrides: [[String]] = [], rules: [String] = [],
                       proxy: EffectiveConfiguration.LocalProxy? = nil, fingerprint: String? = nil,
                       defaults: String? = nil) throws -> Node {
        let yaml = try EffectiveConfiguration.build(source: source, defaults: defaults ?? base,
            overrides: overrides, rules: rules, localProxy: proxy, fingerprint: fingerprint)
        return try XCTUnwrap(Yams.compose(yaml: yaml))
    }

    func testAdvancedDNSIsNotReplacedOrAugmentedWithUnrequestedPolicies() throws {
        let source = """
        dns:
          enable: false
          enhanced-mode: redir-host
          nameserver: [https://resolver.invalid/dns-query]
          nameserver-policy: {"+.internal": [192.0.2.53]}
          proxy-server-nameserver: [9.9.9.9]
          direct-nameserver: [8.8.8.8]
          respect-rules: true
          fake-ip-filter: ["+.lan"]
          future-option: {value: "0001"}
        """
        let result = try build(source, overrides: [["dns", "enable"], ["dns", "nameserver"]])
        XCTAssertEqual(result["dns"]?["enable"]?.bool, true)
        XCTAssertEqual(result["dns"]?["nameserver"]?.sequence?.first?.string, "223.5.5.5")
        XCTAssertEqual(result["dns"]?["enhanced-mode"]?.string, "redir-host")
        XCTAssertNil(result["dns"]?["fallback"])
        for key in ["nameserver-policy", "proxy-server-nameserver", "direct-nameserver", "respect-rules", "fake-ip-filter", "future-option"] {
            XCTAssertEqual(result["dns"]?[key], try Yams.compose(yaml: source)?["dns"]?[key])
        }
    }

    func testTUNOverridesOnlyOwnedFieldsAndDisablesInheritedTUNInNormalMode() throws {
        let source = """
        tun: {enable: true, stack: gvisor, mtu: 9000, auto-route: false, route-exclude-address: [192.0.2.0/24], device: utun8}
        sniffer: {enable: false, force-domain: ["+.example.invalid"], sniff: {QUIC: {ports: [443]}}}
        profile: {store-selected: false, future-option: true}
        """
        let tun = try build(source, overrides: [["tun", "enable"], ["tun", "mtu"], ["tun", "device"], ["profile", "store-selected"]])
        XCTAssertEqual(tun["tun"]?["mtu"]?.int, 1400)
        XCTAssertEqual(tun["tun"]?["stack"]?.string, "gvisor")
        XCTAssertEqual(tun["tun"]?["auto-route"]?.bool, false)
        XCTAssertNil(tun["tun"]?["device"])
        XCTAssertNotNil(tun["tun"]?["route-exclude-address"])
        XCTAssertEqual(tun["sniffer"], try Yams.compose(yaml: source)?["sniffer"])
        XCTAssertEqual(tun["profile"]?["store-selected"]?.bool, true)
        XCTAssertEqual(tun["profile"]?["future-option"]?.bool, true)
        let normal = try build(source, overrides: [["tun", "enable"]], defaults: "tun: {enable: false}")
        XCTAssertEqual(normal["tun"]?["enable"]?.bool, false)
        XCTAssertEqual(normal["tun"]?["stack"]?.string, "gvisor")
    }

    func testGroupAndProviderPoliciesAndUnknownFieldsSurvive() throws {
        let source = """
        unified-delay: false
        tcp-concurrent: false
        global-client-fingerprint: firefox
        proxy-groups:
        - {name: Auto, type: url-test, use: [remote], interval: 57, tolerance: 42, lazy: false}
        proxy-providers:
          remote: {type: http, url: 'https://example.invalid/nodes', interval: 86400, health-check: {enable: true, interval: 123}}
        rule-providers:
          ruleset: {type: inline, behavior: classical, payload: ['DOMAIN,example.invalid']}
        future-field: {nested: [1, "001", true]}
        """
        let result = try build(source)
        let original = try XCTUnwrap(Yams.compose(yaml: source))
        for (key, value) in original.mapping! { XCTAssertEqual(result[key], value, key.string ?? "") }
    }

    func testFlowQuotedKeysAndAliasesSupportRulesAndFingerprintInjection() throws {
        let source = """
        template: &node {type: vless, server: example.invalid, port: 443, password: "00123"}
        'proxies': [{<<: *node, name: One}, {<<: *node, name: Two, client-fingerprint: safari}]
        'rules': ['MATCH,DIRECT']
        """
        let result = try build(source, rules: ["DOMAIN,local.invalid,DIRECT"],
            proxy: .init(name: "MITM-Intercept", port: 8888), fingerprint: "chrome")
        let nodes = try XCTUnwrap(result["proxies"]?.sequence)
        XCTAssertEqual(nodes.count, 3)
        XCTAssertEqual(nodes[0]["port"]?.int, 8888)
        XCTAssertEqual(nodes[1]["client-fingerprint"]?.string, "chrome")
        XCTAssertEqual(nodes[1]["password"]?.string, "00123")
        XCTAssertEqual(nodes[2]["client-fingerprint"]?.string, "safari")
        XCTAssertEqual(result["rules"]?.sequence?.map(\.string), ["DOMAIN,local.invalid,DIRECT", "MATCH,DIRECT"])
    }

    func testMergeSequencePrecedenceAndQuotedMergeKey() throws {
        let result = try build("""
        first: &first {mtu: 8000, stack: gvisor}
        second: &second {mtu: 9000, auto-route: false}
        tun: {<<: [*first, *second], mtu: 1500}
        extension: {"<<": literal}
        """)
        XCTAssertEqual(result["tun"]?["mtu"]?.int, 1500)
        XCTAssertEqual(result["tun"]?["auto-route"]?.bool, false)
        XCTAssertEqual(result["extension"]?[Node("<<", Tag(.str))]?.string, "literal")
    }

    func testRejectsAmbiguityInvalidDocumentsAndReservedNameCollisions() throws {
        for source in ["dns: [", "[]", "dns: {}\ndns: {}", "dns: {enable: true, enable: false}", "dns: {}\n---\ndns: {}"] {
            XCTAssertThrowsError(try build(source), source) { error in
                XCTAssertFalse(error.localizedDescription.contains(source))
            }
        }
        XCTAssertThrowsError(try build("dns: []", overrides: [["dns", "nameserver"]]))
        XCTAssertThrowsError(try build("rules: {}", rules: ["MATCH,DIRECT"]))
        XCTAssertThrowsError(try build("proxies: [{name: MITM-Intercept}]", proxy: .init(name: "MITM-Intercept", port: 8888)))
        XCTAssertThrowsError(try build("proxy-groups: [{name: MITM-Intercept}]", proxy: .init(name: "MITM-Intercept", port: 8888)))
    }

    func testMissingSectionsUseDefaultsAndBuildDoesNotAccumulateLocalRules() throws {
        let source = "rules: [\"MATCH,DIRECT\"]"
        let first = try build(source, rules: ["DOMAIN,local.invalid,DIRECT"])
        let second = try build(source, rules: ["DOMAIN,local.invalid,DIRECT"])
        XCTAssertEqual(first, second)
        XCTAssertEqual(first["rules"]?.sequence?.count, 2)
        XCTAssertEqual(first["dns"]?["enhanced-mode"]?.string, "fake-ip")
        XCTAssertEqual(first["tun"]?["enable"]?.bool, true)
    }
    func testInheritedProjectionUsesMergerAndDistinguishesDefaults() throws {
        let fields = try EffectiveConfiguration.inheritedFields(source: """
        template: &tun {mtu: 8500, auto-route: false}
        tun: {<<: *tun}
        dns: {nameserver: [9.9.9.9]}
        """, defaults: base, paths: ["mtu": ["tun", "mtu"], "route": ["tun", "auto-route"],
            "dns": ["dns", "nameserver"], "stack": ["tun", "stack"], "device": ["tun", "device"],
            "fallback": ["dns", "fallback"]])
        XCTAssertEqual(fields["mtu"]?.value, "8500")
        XCTAssertEqual(fields["mtu"]?.source, "Subscription")
        XCTAssertEqual(fields["route"]?.scalar, "false")
        XCTAssertEqual(fields["dns"]?.value, "9.9.9.9")
        XCTAssertEqual(fields["stack"]?.source, "Ares default")
        XCTAssertEqual(fields["device"]?.source, "Core default")
        // Existing DNS must not gain the application's fallback behind the UI's back.
        XCTAssertEqual(fields["fallback"]?.source, "Core default")
        XCTAssertThrowsError(try EffectiveConfiguration.inheritedFields(source: "dns: [", defaults: base, paths: [:]))
    }

}
