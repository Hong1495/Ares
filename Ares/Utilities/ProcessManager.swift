import Foundation

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
        return try await withCheckedThrowingContinuation { continuation in
            Task.detached {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                
                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = errorPipe
                
                do {
                    try process.run()
                    
                    // Wait for completion (in background thread, won't block MainActor)
                    process.waitUntilExit()
                    
                    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    
                    let output = String(data: outputData, encoding: .utf8) ?? ""
                    let error = String(data: errorData, encoding: .utf8) ?? ""
                    
                    let result = CommandResult(
                        output: output,
                        error: error,
                        exitCode: process.terminationStatus
                    )
                    
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
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
            return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            print("[ProcessManager] Error running \(command): \(error)")
            return ""
        }
    }
    
    /// Check if a port is in use by running lsof
    /// - Parameter port: Port number to check
    /// - Returns: Array of PIDs using the port
    func getPIDsUsingPort(_ port: Int) async -> [Int32] {
        let output = await runSimple(
            "/usr/bin/sudo",
            args: ["-n", "/usr/sbin/lsof", "-i", ":\(port)", "-t"]
        )
        
        return output.components(separatedBy: .newlines)
            .compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
    }
    
    /// Kill process by PID
    /// - Parameter pid: Process ID to kill
    /// - Returns: True if kill command succeeded (does not guarantee process died immediately)
    func killProcess(_ pid: Int32) async -> Bool {
        // Try user kill first (works for own processes)
        let userKill = await runSimple("/bin/kill", args: ["-9", "\(pid)"])
        if userKill.isEmpty { return true } // Empty usually means success for kill command
        
        // If user kill failed/printed error, try sudo kill
        print("[ProcessManager] User kill failed for \(pid), trying sudo...")
        let result = try? await run(executable: "/usr/bin/sudo", arguments: ["-n", "/bin/kill", "-9", "\(pid)"])
        return result?.exitCode == 0
    }
    
    /// Kill all processes matching a pattern
    /// - Parameter pattern: Process name pattern
func killAllProcesses(matching pattern: String) async {
        _ = await runSimple("/usr/bin/sudo", args: ["-n", "/usr/bin/pkill", "-9", "-f", pattern])
    }
}
