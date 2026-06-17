import XCTest

final class CoreInstallVerifierTests: XCTestCase {
    func testManagedCoreRequiresMatchingManifestHash() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let binary = directory.appendingPathComponent("mihomo")
        let manifestURL = directory.appendingPathComponent("manifest.json")
        try Data("#!/bin/sh\necho fake-core\n".utf8).write(to: binary)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)

        let manifest = CoreInstallManifest(
            version: "v1.0.0",
            assetName: "mihomo-darwin-arm64-v1.0.0.gz",
            assetURL: "https://example.com/mihomo.gz",
            sha256: try CoreInstallVerifier.sha256Hex(for: binary),
            installedAt: Date()
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: manifestURL)

        XCTAssertTrue(CoreInstallVerifier.isManagedCoreUsable(binaryURL: binary, manifestURL: manifestURL))

        try Data("#!/bin/sh\necho tampered-core\n".utf8).write(to: binary)
        XCTAssertFalse(CoreInstallVerifier.isManagedCoreUsable(binaryURL: binary, manifestURL: manifestURL))
    }
}
