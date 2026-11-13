import XCTest
import Yams
@testable import SubscriptionKit

final class SceneOverrideDocumentTests: XCTestCase {
    func testDNSProjectionPreservesTypedValuesAndExplicitEmptyLists() throws {
        let text = "respect-rules: true\nfake-ip-filter: []\nhosts: {internal.test: 192.0.2.1}\nproxy-server-nameserver: [1.1.1.1]"
        let encoded = try SceneOverrideDocument.encode(text, section: .dns)
        let rendered = try SceneOverrideDocument.render(encoded, section: .dns)
        let config = try Yams.compose(yaml: DNSConfiguration.apply(source: "{}", overrides: encoded))!
        XCTAssertEqual(config["dns"]?["respect-rules"]?.bool, true)
        XCTAssertEqual(config["dns"]?["fake-ip-filter"]?.sequence?.count, 0)
        XCTAssertEqual(config["hosts"]?["internal.test"]?.string, "192.0.2.1")
        XCTAssertEqual(try SceneOverrideDocument.encode(rendered, section: .dns), encoded)
    }
    func testPolicyEditsReachEffectiveGroupParameters() throws {
        let encoded = try SceneOverrideDocument.encode("Auto: {interval: 120, tolerance: 50, lazy: false}", section: .policy)
        let roundTrip = try SceneOverrideDocument.encode(SceneOverrideDocument.render(encoded, section: .policy), section: .policy)
        XCTAssertEqual(encoded, roundTrip)
        let source = "proxy-groups: [{name: Auto, type: url-test, proxies: [DIRECT], url: 'https://example.test/204', interval: 300}]"
        let groups = try PolicyConfiguration.read(PolicyConfiguration.apply(source: source, overrides: encoded))
        XCTAssertEqual(groups[0].fields["interval"], "120")
        XCTAssertEqual(groups[0].fields["lazy"], "false")
    }
    func testRoutingProjectionPreservesCredentialsUnknownListenerFieldsAndEmptyValues() throws {
        let text = """
        nodes: {Exit: {dialer-proxy: Entry, interface-name: ''}}
        interface: ''
        listeners:
          - {name: Local, type: http, listen: 127.0.0.1, port: 18080, users: [{username: demo, password: '0123'}], future-field: true}
        tunnels: []
        """
        let encoded = try SceneOverrideDocument.encode(text, section: .routing)
        let rendered = try SceneOverrideDocument.render(encoded, section: .routing)
        let restored = try EgressConfiguration.decode(SceneOverrideDocument.encode(rendered, section: .routing))
        XCTAssertEqual(restored, try EgressConfiguration.decode(encoded))
        XCTAssertEqual(restored.nodes["Exit"]?["interface-name"], "")
        let listener = try Yams.compose(yaml: restored.listeners!)!.sequence!.first!
        XCTAssertEqual(listener["users"]?.sequence?.first?["password"]?.string, "0123")
        XCTAssertEqual(listener["future-field"]?.bool, true)
        XCTAssertEqual(try Yams.compose(yaml: restored.tunnels!)?.sequence?.count, 0)
    }
    func testInvalidAndUnknownInputRejectedWithoutDroppingFields() {
        for (section, documents) in [
            (SceneOverrideDocument.Section.dns, ["enable: true", "respect-rules: 'true'", "hosts: []", "hosts: {}\nhosts: {}", "{}\n---\n{}"]),
            (.policy, ["Auto: {interval: [120]}", "Auto: {typo: true}", "Auto: {}\nAuto: {}"]),
            (.routing, ["unknown: true", "interface: 42", "listeners: {}", "nodes: {A: {password: secret}}", "tunnels: null"])
        ] {
            for document in documents { XCTAssertThrowsError(try SceneOverrideDocument.encode(document, section: section), document) }
        }
    }
}
