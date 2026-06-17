import XCTest

final class CoreArchiveExtractorTests: XCTestCase {
    func testZipEntryValidationRejectsUnsafePaths() {
        XCTAssertTrue(CoreArchiveExtractor.zipEntriesAreSafe([
            "mihomo-darwin-arm64",
            "folder/mihomo"
        ]))

        XCTAssertFalse(CoreArchiveExtractor.zipEntriesAreSafe(["../mihomo"]))
        XCTAssertFalse(CoreArchiveExtractor.zipEntriesAreSafe(["/tmp/mihomo"]))
        XCTAssertFalse(CoreArchiveExtractor.zipEntriesAreSafe(["folder\\..\\mihomo"]))
    }

    func testFindCoreBinaryPrefersRealDarwinArm64Binary() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let nested = directory.appendingPathComponent("payload")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("mihomo-folder"),
            withIntermediateDirectories: true
        )
        try Data("hash".utf8).write(to: nested.appendingPathComponent("mihomo-darwin-arm64.sha256"))
        let binary = nested.appendingPathComponent("mihomo-darwin-arm64-v1.0.0")
        try Data("binary".utf8).write(to: binary)

        XCTAssertEqual(
            try CoreArchiveExtractor.findCoreBinary(in: directory)?.standardizedFileURL,
            binary.standardizedFileURL
        )
    }
}
