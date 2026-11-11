import Foundation
import Darwin

/// Async-safe process manager that runs shell commands without blocking MainActor
/// Uses async/await pattern to prevent watchdog terminations
actor ProcessManager {

    /// Result of a shell command execution
    struct CommandResult {
        let output: String
        let error: String
        let exitCode: Int32
    }

    /// Run a shell command asynchronously
    /// - Parameters:
    ///   - executable: Path to executable (e.g., "/usr/bin/sudo")
    ///   - arguments: Command arguments
    ///   - timeout: Optional timeout in seconds
    /// - Returns: Command result with output, error, and exit code
    func run(
        executable: String,
        arguments: [String],
        timeout: TimeInterval? = nil
    ) async throws -> CommandResult {
        let worker = Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            // Files avoid pipe-buffer deadlock even for verbose commands.
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let outURL = directory.appendingPathComponent("stdout")
            let errURL = directory.appendingPathComponent("stderr")
            FileManager.default.createFile(atPath: outURL.path, contents: nil)
            FileManager.default.createFile(atPath: errURL.path, contents: nil)
            let out = try FileHandle(forWritingTo: outURL)
            let err = try FileHandle(forWritingTo: errURL)
            defer { try? out.close(); try? err.close() }
            process.standardOutput = out
            process.standardError = err
            try process.run()
            let deadline = ContinuousClock.now.advanced(by: .seconds(timeout ?? 30))
            while process.isRunning {
                if Task.isCancelled || ContinuousClock.now >= deadline {
                    let cancelled = Task.isCancelled
                    process.terminate()
                    for _ in 0..<50 {
                        if !process.isRunning { break }
                        try? await Task.sleep(for: .milliseconds(20))
                    }
                    // This is the retained child created above, never a discovered PID.
                    if process.isRunning { _ = Darwin.kill(process.processIdentifier, SIGKILL) }
                    process.waitUntilExit()
                    if cancelled { throw CancellationError() }
                    throw URLError(.timedOut)
                }
                try? await Task.sleep(for: .milliseconds(20))
            }
            return CommandResult(
                output: String(decoding: try Data(contentsOf: outURL), as: UTF8.self),
                error: String(decoding: try Data(contentsOf: errURL), as: UTF8.self),
                exitCode: process.terminationStatus)
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    /// Run a simple shell command and return output
    /// - Parameters:
    ///   - command: Full command path
    ///   - args: Arguments array
    /// - Returns: Command output (stdout)
    func runSimple(_ command: String, args: [String]) async -> String {
        do {
            let result = try await run(executable: command, arguments: args)
            guard result.exitCode == 0 else { return "" }
            return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return ""
        }
    }

    /// Check if a port is in use by running lsof
    /// - Parameter port: Port number to check
    /// - Returns: Array of PIDs using the port
    func getPIDsUsingPort(_ port: Int) async -> [Int32] {
        // Try with sudo first (can see all processes including root-owned)
        let output = await runSimple(
            "/usr/bin/sudo",
            args: ["-n", "/usr/sbin/lsof", "-nP", "-iTCP:\(port)", "-sTCP:LISTEN", "-t"]
        )

        let pids = output.components(separatedBy: .newlines)
            .compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }

        // Fallback: If sudo failed (empty result may mean no sudo access),
        // try without sudo to at least detect user-owned processes
        if pids.isEmpty {
            let fallbackOutput = await runSimple(
                "/usr/sbin/lsof",
                args: ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN", "-t"]
            )
            let fallbackPids = fallbackOutput.components(separatedBy: .newlines)
                .compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
            if !fallbackPids.isEmpty {
                return fallbackPids
            }
        }

        return pids
    }

}
