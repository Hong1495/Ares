import XCTest
import Yams
@testable import SubscriptionKit

final class ManagedWorkspaceTests: XCTestCase {
    let base = """
    proxies: [{name: Existing, type: http, server: 127.0.0.1, port: 8080, custom-option: retained}]
    proxy-groups: [{name: Main, type: select, proxies: [Existing]}]
    rules: [MATCH,Main]
    dns: {enable: false}
    """
    func testLocalNodesPreserveSubscriptionAndUnknownFields() throws {
        var draft = ManagedResources.Draft()
        draft.nodes["Private"] = "type: trojan\nserver: example.com\nport: 443\npassword: credential\ntls-extension: retained"
        let result = try ManagedResources.apply(source: base, draft: draft)
        let root = try ManagedResources.document(result)
        XCTAssertEqual(root["proxies"]?.sequence?.count, 2)
        XCTAssertEqual(root["proxies"]?.sequence?.first?["custom-option"]?.string, "retained")
        XCTAssertEqual(root["proxies"]?.sequence?.last?["tls-extension"]?.string, "retained")
        XCTAssertEqual(try ManagedResources.decode(ManagedResources.encode(draft)), draft)
        XCTAssertEqual(try ManagedResources.apply(source: base, draft: .init()), base)
    }
    func testReferencesRejectRemovedNodeAndProvider() throws {
        var draft = ManagedResources.Draft(); draft.removedNodes = ["Existing"]
        let result = try ManagedResources.apply(source: base, draft: draft)
        XCTAssertThrowsError(try PolicyConfiguration.apply(source: result, overrides: #"{"Main":{"type":"select"}}"#))
        let withProvider = "proxy-providers: {Remote: {type: http, url: 'https://example.com', interval: 300}}\nproxy-groups: [{name: Main, type: select, use: [Remote]}]"
        draft = .init(); draft.removedProviders = ["Remote"]
        XCTAssertThrowsError(try PolicyConfiguration.apply(source: ManagedResources.apply(source: withProvider, draft: draft), overrides: #"{"Main":{"type":"select"}}"#))
    }
    func testProviderAuthenticationAndOptionsSurvive() throws {
        var draft = ManagedResources.Draft()
        draft.providers["Remote"] = "type: http\nurl: https://example.com/nodes\ninterval: 300\nheader: {Authorization: ['Bearer fixture']}\nhealth-check: {enable: true, interval: 60, url: https://example.com/check}"
        let result = try ManagedResources.document(ManagedResources.apply(source: base, draft: draft))
        XCTAssertEqual(result["proxy-providers"]?["Remote"]?["header"]?["Authorization"]?.sequence?.first?.string, "Bearer fixture")
        draft.providers["Remote"] = "type: http\nurl: https://example.com\ninterval: 0"
        XCTAssertThrowsError(try ManagedResources.apply(source: base, draft: draft))
        draft.providers["Remote"] = "type: file\npath: ../outside.yaml"
        XCTAssertThrowsError(try ManagedResources.apply(source: base, draft: draft))
    }
    func testLinkImportsAndUnsupportedOptions() throws {
        let uuid = "11111111-1111-1111-1111-111111111111"
        let links = "vless://\(uuid)@example.com:443?security=reality&pbk=public&sid=1234&type=tcp&flow=xtls-rprx-vision#Reality\ntrojan://secret@example.org:443?type=ws&path=%2Fproxy&host=edge.example.org#WebSocket\nss://YWVzLTEyOC1nY206c2VjcmV0@example.net:8388#SS"
        let nodes = try ManagedResources.importLinks(links)
        XCTAssertEqual(nodes.count, 3)
        XCTAssertEqual(try ManagedResources.document(nodes["Reality"]!)["reality-opts"]?["public-key"]?.string, "public")
        XCTAssertEqual(try ManagedResources.document(nodes["WebSocket"]!)["ws-opts"]?["path"]?.string, "/proxy")
        XCTAssertEqual(try ManagedResources.document(nodes["SS"]!)["password"]?.string, "secret")
        XCTAssertThrowsError(try ManagedResources.importLinks("vless://\(uuid)@example.com:443?unknown=1#Node"))
        XCTAssertThrowsError(try ManagedResources.importLinks("ss://YWVzLTEyOC1nY206c2VjcmV0@example.net:8388?plugin=unknown#SS"))
        XCTAssertThrowsError(try ManagedResources.importLinks("trojan://secret@example.org:443#Same\ntrojan://secret@example.org:443#Same"))
    }
    func testDeviceAccessAuthRouteDisableAndConflicts() throws {
        var device = DeviceAccess.Device(name: "Phone", enabled: true, address: "127.0.0.1", port: 10810, username: "phone", password: "fixture-password-only", target: "Main")
        let text = try DeviceAccess.apply(source: base, devices: [device])
        let listener = try ManagedResources.document(text)["listeners"]?.sequence?.first
        XCTAssertEqual(listener?["users"]?.sequence?.first?["username"]?.string, "phone")
        XCTAssertEqual(listener?["proxy"]?.string, "Main")
        XCTAssertEqual(listener?["udp"]?.bool, false)
        device.enabled = false
        XCTAssertEqual(try DeviceAccess.apply(source: base, devices: [device]), base)
        device.enabled = true; device.target = "Missing"
        XCTAssertThrowsError(try DeviceAccess.apply(source: base, devices: [device]))
        device.target = "DIRECT"; device.password = "short"
        XCTAssertThrowsError(try DeviceAccess.apply(source: base, devices: [device]))
        device.password = "fixture-password-only"; device.address = "0.0.0.0"
        XCTAssertThrowsError(try DeviceAccess.apply(source: base, devices: [device]))
        device.address = "127.0.0.1"
        XCTAssertThrowsError(try DeviceAccess.apply(source: base + "\nmixed-port: 10810", devices: [device]))
        var second = device; second.id = UUID(); second.name = "Tablet"
        XCTAssertThrowsError(try DeviceAccess.apply(source: base, devices: [device, second]))
    }
}
