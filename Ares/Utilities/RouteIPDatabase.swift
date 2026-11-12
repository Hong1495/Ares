import Foundation
import Darwin

/// Read-only MMDB decoder. Bounds/depth checks treat unsupported/corrupt data as unknown.
/// No DNS, network lookup or fabricated location fallback.
nonisolated struct RouteIPDatabase: Sendable {
    private let bytes: Data
    private let nodeCount: Int
    private let recordSize: Int
    private let ipVersion: Int
    private let treeSize: Int
    private let dataStart: Int
    enum Failure: Error { case invalid }

    init(url: URL) throws {
        bytes = try Data(contentsOf: url, options: .mappedIfSafe)
        let marker = Data([0xab,0xcd,0xef] + Array("MaxMind.com".utf8))
        guard let range = bytes.range(of: marker, options: .backwards, in: max(0, bytes.count-131072)..<bytes.count) else { throw Failure.invalid }
        var decoder = Decoder(bytes: bytes, base: range.upperBound)
        var cursor = range.upperBound
        guard let metadata = try decoder.value(at: &cursor) as? [String: Any],
              let count = metadata["node_count"] as? Int, count > 0,
              let size = metadata["record_size"] as? Int, [24,28,32].contains(size),
              let version = metadata["ip_version"] as? Int, [4,6].contains(version) else { throw Failure.invalid }
        guard count <= bytes.count / (size / 4) else { throw Failure.invalid }
        nodeCount = count; recordSize = size; ipVersion = version
        treeSize = count * size / 4
        dataStart = treeSize + 16
        guard dataStart < bytes.count else { throw Failure.invalid }
    }

    static func addressBytes(_ address: String) -> [UInt8]? {
        var v4 = in_addr(); var v6 = in6_addr()
        if inet_pton(AF_INET, address, &v4) == 1 { return withUnsafeBytes(of: &v4) { Array($0) } }
        if inet_pton(AF_INET6, address, &v6) == 1 { return withUnsafeBytes(of: &v6) { Array($0) } }
        return nil
    }
    static func isPublic(_ address: String) -> Bool {
        guard let b = addressBytes(address) else { return false }
        if b.count == 4 {
            return !(b[0] == 0 || b[0] == 10 || b[0] == 127 || b[0] >= 224 ||
                (b[0] == 169 && b[1] == 254) || (b[0] == 172 && (16...31).contains(b[1])) ||
                (b[0] == 192 && (b[1] == 168 || (b[1] == 0 && (b[2] == 0 || b[2] == 2)))) || (b[0] == 100 && (64...127).contains(b[1])) ||
                (b[0] == 198 && (b[1] == 18 || b[1] == 19 || (b[1] == 51 && b[2] == 100))) || (b[0] == 203 && b[1] == 0 && b[2] == 113))
        }
        // Global unicast only; reject documentation, local, multicast, mapped and link-local.
        return (b[0] & 0xe0) == 0x20 && !(b[0] == 0x20 && b[1] == 0x01 && b[2] == 0x0d && b[3] == 0xb8)
    }

    func lookup(_ address: String) -> [String: Any]? {
        guard Self.isPublic(address), let raw = Self.addressBytes(address) else { return nil }
        if raw.count == 16 && ipVersion == 4 { return nil }
        let addressBytes = ipVersion == 6 && raw.count == 4 ? Array(repeating: UInt8(0), count: 12) + raw : raw
        var node = 0
        do {
            for byte in addressBytes {
                for bit in (0..<8).reversed() {
                    if node >= nodeCount { break }
                    node = try child(node, right: byte & (1 << bit) != 0)
                }
                if node >= nodeCount { break }
            }
            guard node > nodeCount else { return nil }
            var offset = node - nodeCount + treeSize
            guard offset >= dataStart else { return nil }
            var decoder = Decoder(bytes: bytes, base: dataStart)
            let value = try decoder.value(at: &offset)
            if let code = value as? String { return ["country": ["iso_code": code.uppercased()]] }
            if let codes = value as? [String], let code = codes.first(where: { $0.utf8.count == 2 && $0.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) } }) {
                return ["country": ["iso_code": code.uppercased()]]
            }
            return value as? [String: Any]
        } catch { return nil }
    }
    private func child(_ node: Int, right: Bool) throws -> Int {
        let offset = node * recordSize / 4
        guard offset >= 0, offset + recordSize/4 <= treeSize else { throw Failure.invalid }
        func n(_ start: Int, _ count: Int) -> Int { bytes[start..<start+count].reduce(0) { ($0 << 8) | Int($1) } }
        switch recordSize {
        case 24: return n(offset + (right ? 3 : 0), 3)
        case 28: return right ? (Int(bytes[offset+3] & 0x0f) << 24) | n(offset+4,3) : (Int(bytes[offset+3] >> 4) << 24) | n(offset,3)
        default: return n(offset + (right ? 4 : 0), 4)
        }
    }
    private struct Decoder {
        let bytes: Data
        let base: Int
        mutating func value(at cursor: inout Int, depth: Int = 0) throws -> Any {
            guard depth < 64, cursor >= 0, cursor < bytes.count else { throw Failure.invalid }
            func read(_ count: Int, _ position: inout Int) throws -> Data {
                guard count >= 0, position >= 0, position <= bytes.count-count else { throw Failure.invalid }
                defer { position += count }; return bytes.subdata(in: position..<position+count)
            }
            func number(_ data: Data) -> Int { data.reduce(0) { ($0 << 8) | Int($1) } }
            let control = Int(try read(1,&cursor)[0]); var type = control >> 5
            if type == 1 {
                let size = ((control >> 3) & 3) + 1
                let data = try read(size,&cursor)
                let prefix = size == 4 ? 0 : (control & 7) << (size*8)
                let extra = size == 2 ? 2048 : size == 3 ? 526336 : 0
                var pointer = base + prefix + number(data) + extra
                return try value(at: &pointer, depth: depth+1)
            }
            if type == 0 { type = Int(try read(1,&cursor)[0]) + 7 }
            var size = control & 31
            if size == 29 { size = 29 + number(try read(1,&cursor)) }
            else if size == 30 { size = 285 + number(try read(2,&cursor)) }
            else if size == 31 { size = 65821 + number(try read(3,&cursor)) }
            guard size <= 1_000_000 else { throw Failure.invalid }
            switch type {
            case 2: return String(data: try read(size,&cursor), encoding: .utf8) ?? ""
            case 3:
                guard size == 8 else { throw Failure.invalid }
                let bits = try read(8,&cursor).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
                return Double(bitPattern: bits)
            case 4: return try read(size,&cursor)
            case 5,6,8,9:
                guard size <= 8 else { throw Failure.invalid }; return number(try read(size,&cursor))
            case 7:
                var result: [String: Any] = [:]
                for _ in 0..<size {
                    guard let key = try value(at:&cursor,depth:depth+1) as? String else { throw Failure.invalid }
                    result[key] = try value(at:&cursor,depth:depth+1)
                }; return result
            case 11:
                var result: [Any] = []; for _ in 0..<size { result.append(try value(at:&cursor,depth:depth+1)) }; return result
            case 14: return size != 0
            case 15:
                guard size == 4 else { throw Failure.invalid }
                let bits = try read(4,&cursor).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
                return Double(Float(bitPattern: bits))
            default: throw Failure.invalid
            }
        }
    }
}
