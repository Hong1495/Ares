import XCTest
@testable import SubscriptionKit

final class ConfigurationDiffTests: XCTestCase {
    func testMappingOrderCommentsAndAliasesDoNotCreateChanges() throws {
        XCTAssertTrue(try ConfigurationDiff.compare(before: "tun: {mtu: 1400, enable: true}", after: "# comment\ntun:\n  enable: true\n  mtu: 1400").isEmpty)
        XCTAssertTrue(try ConfigurationDiff.compare(before: "template: &t {mtu: 1400}\ntun: {<<: *t}", after: "template: {mtu: 1400}\ntun: {mtu: 1400}").isEmpty)
    }
    func testNestedAndOrderedListChangesAreNotTruncated() throws {
        let before = "rules:\n" + (0..<120).map { "- DOMAIN,host\($0).invalid,DIRECT" }.joined(separator: "\n")
        let after = "rules:\n" + (0..<120).reversed().map { "- DOMAIN,host\($0).invalid,DIRECT" }.joined(separator: "\n")
        let rows = try ConfigurationDiff.compare(before: before, after: after)
        XCTAssertEqual(rows.count, 120)
        XCTAssertEqual(rows.last?.path, "rules[120]")
        XCTAssertTrue(rows.allSatisfy { $0.before == "Hidden" && $0.after == "Hidden" })
    }
    func testAllAddedRemovedLeavesAndExplicitFalseAreIncluded() throws {
        let rows = try ConfigurationDiff.compare(before: "tun: {enable: false, mtu: 1400}\nrules: [MATCH,DIRECT]", after: "tun: {enable: true}\ndns: {enable: false}")
        XCTAssertTrue(rows.contains { $0.path == "tun.enable" && $0.before == "false" && $0.after == "true" })
        XCTAssertTrue(rows.contains { $0.path == "tun.mtu" && $0.change == "Removed" })
        XCTAssertTrue(rows.contains { $0.path == "dns.enable" && $0.change == "Added" && $0.after == "false" })
        XCTAssertEqual(rows.filter { $0.path.hasPrefix("rules[") }.count, 2)
    }
    func testCredentialsURLsCustomKeysAndTypeChangesCannotLeak() throws {
        let rows = try ConfigurationDiff.compare(before: "{}", after: """
        secret: sentinel-secret
        proxy-providers:
          sentinel-provider:
            url: https://sentinel-host/path?token=sentinel-token
            headers: {Authorization: sentinel-bearer}
        proxies: [{name: sentinel-name, uuid: sentinel-uuid, password: sentinel-password}]
        hosts: {sentinel-domain: 192.0.2.1}
        mode: sentinel-invalid-enum
        """)
        let text = rows.map { $0.path + $0.before + $0.after }.joined()
        XCTAssertFalse(text.contains("sentinel"))
        let changed = try ConfigurationDiff.compare(before: "dns: {}", after: "dns: sentinel-secret")
        XCTAssertEqual(changed.first?.after, "Hidden")
        XCTAssertThrowsError(try ConfigurationDiff.compare(before: "{}", after: "token: [sentinel-secret")) {
            XCTAssertFalse($0.localizedDescription.contains("sentinel"))
        }
    }
}
