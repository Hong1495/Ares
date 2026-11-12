import XCTest
@testable import SubscriptionKit

final class RouteNodeMetadataTests: XCTestCase {
    func testOnlyConcreteAdaptersAreExported() throws {
        let nodes = try RouteNodeMetadata.parse("""
        proxies:
          - {name: Entry, type: vless, server: example.test, uuid: secret, dialer-proxy: Upstream}
          - {name: Direct, type: direct}
        proxy-groups:
          - {name: Group, type: select, proxies: [Entry]}
        """)
        XCTAssertEqual(nodes.count,1)
        XCTAssertEqual(nodes[0].name,"Entry")
        XCTAssertEqual(nodes[0].server,"example.test")
        XCTAssertEqual(nodes[0].dialer,"Upstream")
        XCTAssertEqual(nodes[0].type,"vless")
    }
    func testInvalidDocumentDoesNotProduceInventedNodes() throws {
        XCTAssertThrowsError(try RouteNodeMetadata.parse("[bad"))
        XCTAssertThrowsError(try RouteNodeMetadata.parse("42"))
        XCTAssertTrue(try RouteNodeMetadata.parse("proxies: []").isEmpty)
    }
}
