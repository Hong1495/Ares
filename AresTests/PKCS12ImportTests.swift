import XCTest
import Security

final class PKCS12ImportTests: XCTestCase {
    func testPKCS12ImportProducesIdentity() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let cert = directory.appendingPathComponent("test.crt")
        let key = directory.appendingPathComponent("test.key")
        let p12 = directory.appendingPathComponent("test.p12")

        try runTool("/usr/bin/openssl", arguments: [
            "req", "-x509", "-newkey", "rsa:2048", "-nodes",
            "-keyout", key.path,
            "-out", cert.path,
            "-subj", "/CN=ares.local",
            "-days", "1"
        ])

        try runTool("/usr/bin/openssl", arguments: [
            "pkcs12", "-export",
            "-in", cert.path,
            "-inkey", key.path,
            "-out", p12.path,
            "-passout", "pass:ares"
        ])

        let p12Data = try Data(contentsOf: p12)
        let options = [kSecImportExportPassphrase as String: "ares"]
        var items: CFArray?
        let status = SecPKCS12Import(p12Data as CFData, options as CFDictionary, &items)

        XCTAssertEqual(status, errSecSuccess)
        XCTAssertNotNil(items)
        XCTAssertGreaterThan(CFArrayGetCount(items), 0)

        let first = CFArrayGetValueAtIndex(items, 0)
        let dict = unsafeBitCast(first, to: CFDictionary.self)
        let identity = CFDictionaryGetValue(dict, Unmanaged.passUnretained(kSecImportItemIdentity).toOpaque())
        XCTAssertNotNil(identity)
    }

    private func runTool(_ path: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }
}
