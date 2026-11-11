import XCTest

final class ProfileConfigMergeTests: XCTestCase {
    func testKeepsNodePortsAndNestedSettings() {
        let nodes = """
        proxies:
          - name: Example
            type: vless
            server: example.invalid
            port: 443
            uuid: example
            tls: true
            ws-opts:
              headers:
                mode: preserve
        proxy-groups:
          - name: Proxy
            type: select
            proxies:
              - Example
        rules:
          - MATCH,Proxy
        """
        XCTAssertEqual(ProfileConfigMerge.removingOverrides(from: "port: 7890\n" + nodes), nodes)
    }

    func testRemovesEntireOwnedSectionsIncludingIndentlessLists() {
        let source = """
        dns:
          enable: true
          nameserver:
          - 1.1.1.1
        tun:
          enable: true
        profile:
          store-selected: true
        sniffer:
          enable: true
        proxies: []
        proxy-groups: []
        """
        XCTAssertEqual(ProfileConfigMerge.removingOverrides(from: source), "proxies: []\nproxy-groups: []")
    }

    func testPreservesGeodataURLsAsACompleteSection() {
        let source = """
        geox-url:
          geoip: https://example.invalid/geoip.dat
          geosite: https://example.invalid/geosite.dat
        proxies: [{name: Example, type: vless, port: 443}]
        """
        XCTAssertEqual(ProfileConfigMerge.removingOverrides(from: "mixed-port: 7890\n" + source), source)
    }

    func testQuotedRootKeysAndFlowValues() {
        let source = "\"dns\": {enable: true}\n'port' : 7890\nproxies: [{name: Example, port: 443}]"
        XCTAssertEqual(ProfileConfigMerge.removingOverrides(from: source), "proxies: [{name: Example, port: 443}]")
    }

}
