import Foundation

/// Async-safe file manager that performs all I/O operations off the main thread
/// Prevents MainActor blocking caused by synchronous file operations
actor AsyncFileManager {
    
    /// Read text file contents asynchronously
    /// - Parameter path: URL to the file
    /// - Returns: File contents as String
    /// - Throws: File reading errors
    func readText(from path: URL) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            Task.detached {
                do {
                    let content = try String(contentsOf: path, encoding: .utf8)
                    continuation.resume(returning: content)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Write text to file asynchronously
    /// - Parameters:
    ///   - content: Text content to write
    ///   - path: Destination URL
    ///   - atomic: Whether to write atomically (default: true)
    /// - Throws: File writing errors
    func writeText(_ content: String, to path: URL, atomically atomic: Bool = true) async throws {
        try await withCheckedThrowingContinuation { continuation in
            Task.detached {
                do {
                    try content.write(to: path, atomically: atomic, encoding: .utf8)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        } as Void
    }
    
    /// Check if file exists at path
    /// - Parameter path: URL to check
    /// - Returns: true if file exists
    nonisolated func fileExists(at path: URL) -> Bool {
        FileManager.default.fileExists(atPath: path.path)
    }
    
    /// Create directory if it doesn't exist
    /// - Parameter path: Directory URL
    /// - Throws: Directory creation errors
    func createDirectoryIfNeeded(at path: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            Task.detached {
                do {
                    try FileManager.default.createDirectory(
                        at: path,
                        withIntermediateDirectories: true,
                        attributes: nil
                    )
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        } as Void
    }
}
