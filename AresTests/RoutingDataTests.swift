import Foundation
import XCTest

final class RoutingDataTests: XCTestCase {
    func testAllConnectionsAndTrafficSurviveAggregation() {
        let inputs = (0..<20_000).map { input("\($0)", destination: $0 % 2 == 0 ? "8.8.8.8" : "1.1.1.1") }
        let snapshot = RouteSnapshot.build(inputs: inputs + [inputs[0]], nodes: [:], locations: [:])
        XCTAssertEqual(snapshot.connectionCount, 20_000)
        XCTAssertEqual(snapshot.routes.count, 2)
        XCTAssertEqual(snapshot.upload, 200_000)
        XCTAssertEqual(snapshot.download, 400_000)
        XCTAssertEqual(snapshot.unlocatedCount, 20_000)
    }
    func testLocationDoesNotChangeIdentityOrInventEgress() {
        let node = RouteSnapshot.Node(name:"Proxy",server:"8.8.8.8",type:"vless",dialer:"Upstream")
        let inputs = [input("one",destination:"1.1.1.1")]
        let empty = RouteSnapshot.build(inputs:inputs,nodes:["Proxy":node],locations:[:])
        let located = RouteSnapshot.build(inputs:inputs,nodes:["Proxy":node],locations:["8.8.8.8":.init(longitude:10,latitude:20,label:"Example",precision:"Country estimate")])
        XCTAssertEqual(empty.routes[0].id, located.routes[0].id)
        XCTAssertEqual(located.routes[0].chain, ["Proxy","Group","Proxy"])
        XCTAssertEqual(located.routes[0].endpoints.filter { $0.location != nil }.count, 1)
        XCTAssertNil(located.routes[0].endpoints.first { $0.name == "Remote egress" }?.location)
        XCTAssertEqual(located.connectionCount,1)
    }
    func testNonPublicAndFakeAddressesRemainUnknown() {
        for address in ["198.18.0.1","192.168.1.1","127.0.0.1","100.64.0.1","192.0.2.1","198.51.100.1","203.0.113.1","::1","fc00::1","2001:db8::1","proxy.example"] {
            XCTAssertFalse(RouteIPDatabase.isPublic(address),address)
        }
        for address in ["8.8.8.8","192.0.3.1","198.51.101.1","2001:4860::8888"] { XCTAssertTrue(RouteIPDatabase.isPublic(address),address) }
    }
    func testMMDBTreeWidthsAndMetaCountryRecords() throws {
        // Synthetic fixtures: one tree node, both branches point to a record.
        // Exercises MMDB 24/28/32-bit layouts without downloaded/private data.
        for width in [24,28,32] {
            let records = [string("US"), array([string("google"),string("us")]), map([("country",map([("iso_code",string("GB"))]))])]
            for (index, record) in records.enumerated() {
                let url = try fixture(width:width,record:record)
                defer { try? FileManager.default.removeItem(at:url) }
                let db = try RouteIPDatabase(url:url)
                for address in ["8.8.8.8","2001:4860::8888"] {
                    XCTAssertEqual((db.lookup(address)?["country"] as? [String:String])?["iso_code"],index == 2 ? "GB" : "US")
                }
                XCTAssertNil(db.lookup("198.18.0.1"))
            }
        }
    }
    func testMMDBCoordinatesAndCorruptPointer() throws {
        let record = map([("location",map([("latitude",double(51.51)),("longitude",double(-0.09))]))])
        let url = try fixture(width:24,record:record)
        defer { try? FileManager.default.removeItem(at:url) }
        let db = try RouteIPDatabase(url:url)
        let location = db.lookup("8.8.8.8")?["location"] as? [String:Double]
        XCTAssertEqual(location?["latitude"],51.51)
        XCTAssertEqual(location?["longitude"],-0.09)
        // A pointer to itself must terminate at the decoder depth bound.
        let corrupt = try fixture(width:24,record:Data([0x20,0]))
        defer { try? FileManager.default.removeItem(at:corrupt) }
        XCTAssertNil(try RouteIPDatabase(url:corrupt).lookup("8.8.8.8"))
        try Data([1,2,3]).write(to:url)
        XCTAssertThrowsError(try RouteIPDatabase(url:url))
    }
    private func input(_ id:String,destination:String)->RouteSnapshot.Input {
        .init(id:id,application:"Safari",host:destination,destinationIP:destination,rule:"RuleSet",chains:["Proxy","Group","Proxy"],upload:10,download:20)
    }
    private func string(_ value:String)->Data { Data([0x40 | UInt8(value.utf8.count)]) + Data(value.utf8) }
    private func integer(_ value:Int)->Data { Data([0xc1,UInt8(value)]) }
    private func array(_ values:[Data])->Data { Data([UInt8(values.count),4]) + values.reduce(Data(),+) }
    private func map(_ values:[(String,Data)])->Data { Data([0xe0 | UInt8(values.count)]) + values.reduce(Data()) { $0 + string($1.0) + $1.1 } }
    private func double(_ value:Double)->Data { Data([0x68]) + Data((0..<8).reversed().map { UInt8(truncatingIfNeeded:value.bitPattern >> ($0*8)) }) }
    private func fixture(width:Int,record:Data)throws->URL {
        let tree:Data
        switch width {
        case 24: tree=Data([0,0,17,0,0,17])
        case 28: tree=Data([0,0,17,0,0,0,17])
        default: tree=Data([0,0,0,17,0,0,0,17])
        }
        let metadata=map([("node_count",integer(1)),("record_size",integer(width)),("ip_version",integer(6))])
        let data=tree + Data(repeating:0,count:16) + record + Data([0xab,0xcd,0xef]) + Data("MaxMind.com".utf8) + metadata
        let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".mmdb")
        try data.write(to:url);return url
    }
}
