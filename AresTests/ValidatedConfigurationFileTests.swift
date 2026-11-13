import XCTest

final class ValidatedConfigurationFileTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("AresConfigCommit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    func testRejectionAndValidatorErrorKeepOldFileAndCleanCandidate() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let target = dir.appendingPathComponent("config.yaml")
        try "old-config".write(to: target, atomically: true, encoding: .utf8)
        for failWithError in [false, true] {
            do {
                try await ValidatedConfigurationFile.commit("new-config", to: target) { candidate in
                    XCTAssertEqual(candidate.deletingLastPathComponent().path, dir.path)
                    XCTAssertEqual(try String(contentsOf: candidate), "new-config")
                    XCTAssertEqual(try String(contentsOf: target), "old-config")
                    if failWithError { throw URLError(.timedOut) }
                    return false
                }
                XCTFail("Invalid candidate must not commit")
            } catch {}
            XCTAssertEqual(try String(contentsOf: target), "old-config")
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), ["config.yaml"])
        }
    }
    func testSuccessfulValidationCommitsAndCleansCandidate() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let target = dir.appendingPathComponent("config.yaml")
        try await ValidatedConfigurationFile.commit("accepted", to: target) { candidate in
            XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
            return try String(contentsOf: candidate) == "accepted"
        }
        XCTAssertEqual(try String(contentsOf: target), "accepted")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), ["config.yaml"])
    }
    func testCancellationAfterValidationDoesNotReplaceOldFile() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let target = dir.appendingPathComponent("config.yaml")
        try "old-config".write(to: target, atomically: true, encoding: .utf8)
        let task = Task {
            try await ValidatedConfigurationFile.commit("cancelled", to: target) { _ in
                withUnsafeCurrentTask { $0?.cancel() }
                return true
            }
        }
        do { try await task.value; XCTFail("Cancelled candidate committed") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(try String(contentsOf: target), "old-config")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), ["config.yaml"])
    }
}
