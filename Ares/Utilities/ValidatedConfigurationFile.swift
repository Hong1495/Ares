import Foundation

/// Candidate and destination share the resource directory. Validation never overwrites
/// the working file; atomic replacement occurs only after an affirmative result.
nonisolated enum ValidatedConfigurationFile {
    enum Failure: LocalizedError {
        case rejected
        var errorDescription: String? { "Generated configuration is invalid. The previous configuration was kept." }
    }

    static func commit(_ content: String, to destination: URL,
                       validate: (URL) async throws -> Bool) async throws {
        let candidate = destination.deletingLastPathComponent()
            .appendingPathComponent("candidate-\(UUID().uuidString).yaml")
        defer { try? FileManager.default.removeItem(at: candidate) }
        try content.write(to: candidate, atomically: true, encoding: .utf8)
        guard try await validate(candidate) else { throw Failure.rejected }
        try Task.checkCancellation()
        try content.write(to: destination, atomically: true, encoding: .utf8)
    }
}
