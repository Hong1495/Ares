import XCTest
@testable import SubscriptionKit

final class PolicyUsageTests: XCTestCase {
    func testRulesAndApplicationsAndSubRules() throws {
        let source = """
        rules:
          - DOMAIN-SUFFIX,example.test,US
          - IP-CIDR,192.0.2.0/24,US,no-resolve
          - AND,((NETWORK,tcp),(DST-PORT,443)),US
          - SUB-RULE,(NETWORK,tcp),children
          - FUTURE-RULE,value,US
          - MATCH,US
        sub-rules:
          children:
            - PROCESS-NAME,Browser,US
        """
        let rules = "# comment\nPROCESS-PATH,/Applications/App.app/Contents/MacOS/App,US\nOR,((NETWORK,tcp),(NETWORK,udp)),US"
        let result = try PolicyUsage.read(source: source, localRules: rules)
        XCTAssertEqual(result.references(to: "US").count, 7)
        XCTAssertEqual(result.references.filter { $0.kind == "Application" }.map(\.name), ["App", "Browser"])
        XCTAssertTrue(result.references(to: "children").isEmpty)
        XCTAssertEqual(result.issues.count, 1)
        XCTAssertEqual(Set(result.references.map(\.id)).count, result.references.count)
    }

    func testDependenciesUseOverridesAndExcludeCredentials() throws {
        let source = """
        proxies:
          - {name: Exit, type: http, password: fixture-password, dialer-proxy: Old}
        proxy-groups:
          - {name: Route, type: select, proxies: [US], include-all: true}
        listeners:
          - {name: Original, proxy: Old, users: [{username: fixture-user, password: fixture-password}]}
        tunnels:
          - {proxy: US}
        proxy-providers:
          Remote: {type: http, url: 'https://example.test/fixture-token'}
        """
        var egress = EgressConfiguration.Overrides()
        egress.nodes = ["Exit": ["dialer-proxy": "US"]]
        egress.listeners = "[{name: Access, proxy: US}]"
        let devices = [DeviceAccess.Device(name: "Phone", enabled: false, username: "fixture-user", password: "fixture-password", target: "US")]
        let result = try PolicyUsage.read(source: source, localRules: "", egress: egress, devices: devices)
        XCTAssertEqual(Set(result.references(to: "US").map(\.kind)), ["Group", "Chain", "Listener", "Tunnel", "Device"])
        XCTAssertTrue(result.references(to: "Old").isEmpty)
        XCTAssertEqual(result.references.last?.detail, "Disabled")
        XCTAssertEqual(result.issues.count, 1)
        let projection = result.references.map { $0.name + $0.detail }.joined()
        for secret in ["fixture-password", "fixture-user", "fixture-token"] { XCTAssertFalse(projection.contains(secret)) }
        egress.listeners = "[]"
        let cleared = try PolicyUsage.read(source: source, localRules: "", egress: egress)
        XCTAssertFalse(cleared.references.contains { $0.kind == "Listener" })
    }

    func testReferencesAreNotCapped() throws {
        let rules = (0..<120).map { "DOMAIN,host\($0).test,US" }.joined(separator: "\n")
        let result = try PolicyUsage.read(source: "{}", localRules: rules)
        XCTAssertEqual(result.references(to: "US").count, 120)
        XCTAssertTrue(result.issues.isEmpty)
    }
}
