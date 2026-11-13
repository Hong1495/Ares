import XCTest
@testable import SubscriptionKit

final class NetworkFormDocumentTests: XCTestCase {
    func testDNSFormRoundTripAndStrictProjection() throws {
        let text = "'*.test': ['https://dns.test/query?a=b', '192.0.2.53']\nlocal.test: '192.0.2.3'"
        let entries = try NetworkFormDocument.entries(text)
        XCTAssertEqual(try NetworkFormDocument.entries(NetworkFormDocument.entries(entries)), entries)
        XCTAssertFalse(entries[1].isList)
        XCTAssertThrowsError(try NetworkFormDocument.entries("geoip: true"))
        XCTAssertThrowsError(try NetworkFormDocument.entries("a: one\na: two"))
        XCTAssertThrowsError(try NetworkFormDocument.entries([.init(key: "a", values: ["x"]), .init(key: "a", values: ["y"])]))
        let values = ["+.test", "", "1.1.1.1", "https://dns.test/#Proxy"]
        XCTAssertEqual(try NetworkFormDocument.strings(NetworkFormDocument.strings(values)), values)
    }
    func testListenerEditingPreservesCredentialsUnknownAndOtherRows() throws {
        let source = "- {name: Local, type: mixed, listen: 127.0.0.1, port: 10808, users: [{username: user, password: secret}], certificate: existing, custom: {preserve: true}}\n- {name: Advanced, type: hysteria2, port: 10810, password: hidden}"
        let rows = try NetworkFormDocument.records(source, section: .listeners)
        XCTAssertNotNil(rows[0].fields)
        XCTAssertNil(rows[1].fields)
        XCTAssertFalse(String(describing: rows).contains("secret"))
        let edited = try NetworkFormDocument.saveRecord(source, section: .listeners, index: 0, fields: ["port": "10811"])
        XCTAssertTrue(edited.contains("secret")); XCTAssertTrue(edited.contains("certificate")); XCTAssertTrue(edited.contains("custom")); XCTAssertTrue(edited.contains("hysteria2"))
        XCTAssertEqual(try NetworkFormDocument.records(edited, section: .listeners)[0].fields?["port"], "10811")
        XCTAssertThrowsError(try NetworkFormDocument.saveRecord(source, section: .listeners, index: 0, fields: ["port": "70000"]))
        XCTAssertThrowsError(try NetworkFormDocument.saveRecord(source, section: .listeners, index: nil, fields: rows[0].fields!))
        XCTAssertThrowsError(try NetworkFormDocument.removeRecord(source, index: 5))
        XCTAssertEqual(try NetworkFormDocument.records(NetworkFormDocument.removeRecord(source, index: 0), section: .listeners).count, 1)
    }
    func testFormsComposeIntoValidatedEgress() throws {
        let listener = try NetworkFormDocument.saveRecord("[]", section: .listeners, index: nil, fields: ["name": "Local", "type": "mixed", "listen": "127.0.0.1", "port": "10808", "udp": "true", "proxy": "Route"])
        let forward = try NetworkFormDocument.saveRecord("[]", section: .tunnels, index: nil, fields: ["address": "127.0.0.1:10809", "target": "example.test:443", "network": "tcp,udp", "proxy": "Route"])
        var edits = EgressConfiguration.Overrides(); edits.listeners = listener; edits.tunnels = forward
        let result = try EgressConfiguration.apply(source: "proxy-groups: [{name: Route, type: select, proxies: [DIRECT]}]", overrides: EgressConfiguration.encode(edits))
        XCTAssertEqual(try EgressConfiguration.endpoints(configuration: result).count, 4)
        let malformed = try NetworkFormDocument.saveRecord(forward, section: .tunnels, index: 0, fields: ["address": "wrong"])
        edits.tunnels = malformed
        XCTAssertThrowsError(try EgressConfiguration.apply(source: "{}", overrides: EgressConfiguration.encode(edits)))
    }
}
