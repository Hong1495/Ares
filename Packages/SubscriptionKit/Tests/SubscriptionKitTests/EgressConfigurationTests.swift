import XCTest
import Yams
@testable import SubscriptionKit

final class EgressConfigurationTests: XCTestCase {
    let source = """
    proxies:
      - {name: Entry, type: http, server: 127.0.0.1, port: 18081, password: keep, unknown: preserved}
      - {name: Exit, type: http, server: 127.0.0.1, port: 18082}
    proxy-groups: [{name: Select, type: select, proxies: [Entry]}]
    rules: [MATCH,DIRECT]
    """
    func testChainInterfaceAndUnknownPreservation() throws {
        var edits = EgressConfiguration.Overrides()
        edits.nodes = ["Exit": ["dialer-proxy": "Select", "interface-name": "en0"]]
        edits.interface = "en1"
        let text = try EgressConfiguration.apply(source: source, overrides: EgressConfiguration.encode(edits))
        let node = try Yams.compose(yaml: text)!
        XCTAssertEqual(node["proxies"]?.sequence?.first?["password"]?.string, "keep")
        XCTAssertEqual(node["proxies"]?.sequence?.first?["unknown"]?.string, "preserved")
        let info = try EgressConfiguration.read(text)
        XCTAssertEqual(info.nodes[1].dialer, "Select")
        XCTAssertEqual(info.nodes[1].interface, "en0")
        XCTAssertEqual(info.interface, "en1")
        XCTAssertEqual(try EgressConfiguration.apply(source: source, overrides: EgressConfiguration.empty), source)
    }
    func testCyclesReferencesAndRemovedNodesRejected() throws {
        for nodes in [["Entry": ["dialer-proxy": "Select"]], ["Entry": ["dialer-proxy": "Exit"], "Exit": ["dialer-proxy": "Entry"]], ["Entry": ["dialer-proxy": "Missing"]], ["Removed": ["interface-name": "en0"]], ["Entry": ["password": "bad"]], ["Entry": ["interface-name": "x y"]]] {
            var edits = EgressConfiguration.Overrides(); edits.nodes = nodes
            XCTAssertThrowsError(try EgressConfiguration.apply(source: source, overrides: EgressConfiguration.encode(edits)))
        }
    }
    func testExplicitEmptyClearsAndInheritanceRestores() throws {
        let original = source.replacingOccurrences(of: "name: Exit,", with: "name: Exit, dialer-proxy: Entry,")
        var edits = EgressConfiguration.Overrides(); edits.nodes = ["Exit": ["dialer-proxy": ""]]
        XCTAssertEqual(try EgressConfiguration.read(EgressConfiguration.apply(source: original, overrides: EgressConfiguration.encode(edits))).nodes[1].dialer, "")
        XCTAssertEqual(try EgressConfiguration.read(EgressConfiguration.apply(source: original, overrides: EgressConfiguration.empty)).nodes[1].dialer, "Entry")
    }
    func testListenersTunnelAndAuthPreservation() throws {
        var edits = EgressConfiguration.Overrides()
        edits.listeners = "- {name: Local, type: mixed, listen: 127.0.0.1, port: 10808, proxy: Select, users: [{username: demo, password: secret}]}"
        edits.tunnels = "- {network: [tcp, udp], address: '[::1]:10809', target: 'example.test:443', proxy: DIRECT}"
        let text = try EgressConfiguration.apply(source: source, overrides: EgressConfiguration.encode(edits))
        XCTAssertEqual(try EgressConfiguration.endpoints(configuration: text).count, 4)
        XCTAssertTrue(text.contains("secret"))
        XCTAssertTrue(try EgressConfiguration.read(text).listeners.contains("Local"))
    }
    func testPortsTransportAndWildcardConflicts() throws {
        for listeners in [
            "- {name: A, type: http, listen: 127.0.0.1, port: 7890}",
            "- {name: A, type: mixed, listen: 0.0.0.0, port: 10808}\n- {name: B, type: http, listen: 127.0.0.1, port: 10808}",
            "- {name: A, type: http, listen: 127.0.0.1, port: 9097}"] {
            var edits = EgressConfiguration.Overrides(); edits.listeners = listeners
            XCTAssertThrowsError(try EgressConfiguration.apply(source: source + "\nmixed-port: 7890\nexternal-controller: 127.0.0.1:9097", overrides: EgressConfiguration.encode(edits)))
        }
        var edits = EgressConfiguration.Overrides()
        edits.listeners = "- {name: A, type: http, listen: 127.0.0.1, port: 10808}"
        edits.tunnels = "- udp,127.0.0.1:10808,127.0.0.1:8080,DIRECT"
        XCTAssertNoThrow(try EgressConfiguration.apply(source: source, overrides: EgressConfiguration.encode(edits)))
    }
    func testInvalidListenersAndTunnelsRejected() throws {
        for value in ["{}", "- {name: A, type: tproxy, listen: 127.0.0.1, port: 1080}", "- {name: A, type: http, port: 1080}", "- {name: A, type: http, listen: localhost, port: 1080}", "- {name: A, type: http, listen: 127.0.0.1, port: 0}", "- {name: A, type: http, listen: 127.0.0.1, port: 1080, proxy: Missing}", "- {name: A, type: http, listen: 127.0.0.1, port: 1080, port: 1081}"] {
            var edits = EgressConfiguration.Overrides(); edits.listeners = value
            XCTAssertThrowsError(try EgressConfiguration.apply(source: source, overrides: EgressConfiguration.encode(edits)))
        }
        for value in ["- {network: [sctp], address: '127.0.0.1:1080', target: 'example.test:80'}", "- tcp,127.0.0.1:1080,invalid", "- {network: [], address: '127.0.0.1:1080', target: 'example.test:80'}", "- tcp,127.0.0.1:1080,example.test:80,Missing"] {
            var edits = EgressConfiguration.Overrides(); edits.tunnels = value
            XCTAssertThrowsError(try EgressConfiguration.apply(source: source, overrides: EgressConfiguration.encode(edits)))
        }
    }
    func testInactiveComplexInheritedListenerSurvives() throws {
        let original = source + "\nlisteners: [{name: Existing, type: shadowsocks, listen: 127.0.0.1, port: 1080, password: preserved}]"
        var edits = EgressConfiguration.Overrides(); edits.interface = "en0"
        XCTAssertTrue(try EgressConfiguration.apply(source: original, overrides: EgressConfiguration.encode(edits)).contains("shadowsocks"))
        XCTAssertEqual(try EgressConfiguration.decode(EgressConfiguration.encode(edits)), edits)
    }
}
