import XCTest
import Yams
@testable import SubscriptionKit

final class ConfigurationAuditTests: XCTestCase {
    private func audit(_ yaml: String, _ json: String = """
    {"mode":"rule","port":7892,"allow-lan":false,"tun":{"enable":true,"stack":"System","mtu":1400}}
    """) throws -> [ConfigurationAudit.Row] {
        try ConfigurationAudit.compare(configuration: yaml, response: Data(json.utf8))
    }
    func testTypedComparisonAndCoreStackNormalization() throws {
        let rows = try audit("""
        mode: rule
        port: 7892
        allow-lan: false
        tun: {enable: true, stack: system, mtu: 9000}
        """)
        for key in ["mode", "port", "allow-lan", "tun.enable", "tun.stack"] {
            XCTAssertEqual(rows.first { $0.id == key }?.status, .match, key)
        }
        XCTAssertEqual(rows.first { $0.id == "tun.mtu" }?.status, .different)
        XCTAssertEqual(rows.first { $0.id == "tun.mtu" }?.running, "1400")
    }
    func testDoesNotTreatUnexposedOrMissingFieldsAsVerified() throws {
        let rows = try audit("""
        dns: {nameserver: ['https://resolver.invalid/?token=private-secret']}
        proxies: [{name: secret-node, password: private-secret}]
        secret: private-secret
        keep-alive-interval: 15
        tun: {enable: true}
        """)
        XCTAssertEqual(rows.first { $0.id == "dns" }?.status, .unavailable)
        XCTAssertEqual(rows.first { $0.id == "keep-alive-interval" }?.status, .unavailable)
        XCTAssertEqual(rows.first { $0.id == "port" }?.status, .unspecified)
        XCTAssertFalse(rows.contains { $0.id == "secret" })
        XCTAssertFalse(rows.contains { ($0.configured + $0.running).contains("private-secret") })
        XCTAssertFalse(rows.contains { ($0.configured + $0.running).contains("secret-node") })
    }
    func testDisabledTUNIsDifferentButItsDormantParametersAreNotFailures() throws {
        let rows = try audit("tun: {enable: true, mtu: 9000}", "{\"mode\":\"rule\",\"tun\":{\"enable\":false}}")
        XCTAssertEqual(rows.first { $0.id == "tun.enable" }?.status, .different)
        XCTAssertEqual(rows.first { $0.id == "tun.mtu" }?.status, .inactive)
    }
    func testAliasesAreComparedAndBooleanIsNotAnInteger() throws {
        let rows = try audit("template: &t {enable: true}\ntun: {<<: *t}\nport: true")
        XCTAssertEqual(rows.first { $0.id == "tun.enable" }?.status, .match)
        XCTAssertEqual(rows.first { $0.id == "port" }?.status, .different)
    }
    func testMalformedDocumentsAndResponsesFailWithoutDisclosingContents() throws {
        for json in ["{}", "[]", "not-json-private-secret", "{\"mode\":1,\"tun\":{}}"] {
            XCTAssertThrowsError(try audit("tun: {enable: true}", json)) {
                XCTAssertFalse($0.localizedDescription.contains("private-secret"))
            }
        }
        XCTAssertThrowsError(try audit("password: [private-secret")) {
            XCTAssertFalse($0.localizedDescription.contains("private-secret"))
        }
    }
    func testStartupContractRejectsMissingAndWrongListenerBeforeReadiness() throws {
        let yaml = """
        port: 7892
        socks-port: 7891
        mixed-port: 7890
        mode: rule
        log-level: info
        allow-lan: false
        ipv6: false
        find-process-mode: always
        tun: {enable: false}
        """
        let json = """
        {"port":7892,"socks-port":7891,"mixed-port":7890,"mode":"rule","log-level":"info","allow-lan":false,"ipv6":false,"find-process-mode":"always","tun":{"enable":false}}
        """
        XCTAssertNoThrow(try ConfigurationAudit.verifyStartup(configuration: yaml, response: Data(json.utf8)))
        XCTAssertThrowsError(try ConfigurationAudit.verifyStartup(configuration: yaml, response: Data(json.replacingOccurrences(of: "7890", with: "0").utf8)))
        XCTAssertThrowsError(try ConfigurationAudit.verifyStartup(configuration: yaml, response: Data("{\"mode\":\"rule\",\"tun\":{\"enable\":false}}".utf8)))
    }

    func testRecoveryCapturesLiveModeWithoutChangingOtherRequiredFields() throws {
        let yaml = """
        port: 7892
        socks-port: 7891
        mixed-port: 7890
        mode: rule
        log-level: info
        allow-lan: false
        ipv6: false
        find-process-mode: always
        tun: {enable: false}
        """
        let json = """
        {"port":7892,"socks-port":7891,"mixed-port":7890,"mode":"global","log-level":"debug","allow-lan":false,"ipv6":false,"find-process-mode":"always","tun":{"enable":false}}
        """
        let snapshot = try ConfigurationAudit.recoveryConfiguration(configuration: yaml, response: Data(json.utf8))
        let parsed = try Yams.compose(yaml: snapshot)
        XCTAssertEqual(parsed?["mode"]?.string, "global")
        XCTAssertEqual(parsed?["log-level"]?.string, "debug")
        XCTAssertTrue(yaml.contains("mode: rule"))
        XCTAssertThrowsError(try ConfigurationAudit.recoveryConfiguration(configuration: yaml, response: Data(json.replacingOccurrences(of: "7890", with: "0").utf8)))
    }

}
