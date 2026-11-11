import Foundation
import AppKit

/// Service to handle privilege escalation via sudoers
class PrivilegeService {
    static let shared = PrivilegeService()

    private init() {}

    /// Check if we have password-less sudo access (Async)
    func checkPrivileges() async -> Bool {
        let clashPath = await CoreManager.shared.activeBinaryPath()
        guard FileManager.default.isExecutableFile(atPath: clashPath) else { return false }
        let runner = ProcessManager()
        // Read-only permission checks; never use pkill as a capability probe.
        for arguments in [["-n", clashPath, "-v"], ["-n", "/usr/sbin/lsof", "-v"]] {
            guard let result = try? await runner.run(executable: "/usr/bin/sudo", arguments: arguments, timeout: 5), result.exitCode == 0 else { return false }
        }
        return true
    }

    /// Verify that the sudoers file contains the correct clash-meta binary path.
    /// Returns true if paths are consistent, false if stale/mismatched.
    /// This detects migration issues (e.g. M1→M4, rebuild with new DerivedData path).
    func verifySudoersPathConsistency() async -> Bool {
        let currentClashPath = await CoreManager.shared.activeBinaryPath()
        return await Task.detached(priority: .userInitiated) {
            guard FileManager.default.isExecutableFile(atPath: currentClashPath) else { return false }

            let sudoersPath = "/etc/sudoers.d/ares_rules_v3"

            // Check if sudoers file exists
            guard FileManager.default.fileExists(atPath: sudoersPath) else {
                // No sudoers file at all → needs install, not a "stale" issue
                return false
            }

            // Try to read the sudoers file content via sudo cat
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
            proc.arguments = ["-n", "/bin/cat", sudoersPath]

            let outPipe = Pipe()
            proc.standardOutput = outPipe
            proc.standardError = Pipe()

            try? proc.run()
            proc.waitUntilExit()

            // If sudo -n cat fails (no NOPASSWD for cat), fall back to checking
            // if the current clash-meta path works with sudo -n
            if proc.terminationStatus != 0 {
                // Can't read file, but we can test if the current binary path is whitelisted
                let testProc = Process()
                testProc.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
                testProc.arguments = ["-n", currentClashPath, "-v"]
                testProc.standardOutput = Pipe()
                testProc.standardError = Pipe()
                try? testProc.run()
                testProc.waitUntilExit()
                return testProc.terminationStatus == 0
            }

            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            guard let content = String(data: data, encoding: .utf8) else {
                return false
            }

            // Check if the current clash-meta path is present in sudoers syntax.
            return content.contains(SudoersEscaper.commandPath(currentClashPath))
        }.value
    }

    /// Check and auto-repair sudoers on startup.
    /// Detects stale paths from Mac migration or rebuild, and reinstalls if needed.
    func checkAndRepairSudoers() async {
        await MainActor.run {
            ClashViewModel.shared.addLog("[Privilege] 🔍 Checking sudoers path consistency...")
        }

        let isConsistent = await verifySudoersPathConsistency()

        if !isConsistent {
            await MainActor.run {
                ClashViewModel.shared.addLog("[Privilege] ⚠️ Sudoers path mismatch detected (migration/rebuild). Reinstalling...")
            }

            let success = await installSudoers()

            await MainActor.run {
                if success {
                    ClashViewModel.shared.addLog("[Privilege] ✅ Sudoers auto-repaired successfully")
                } else {
                    ClashViewModel.shared.addLog("[Privilege] ❌ Sudoers auto-repair failed - manual intervention needed")
                }
            }
        } else {
            await MainActor.run {
                ClashViewModel.shared.addLog("[Privilege] ✅ Sudoers paths are consistent")
            }
        }
    }

    /// Install sudoers configuration
    func installSudoers() async -> Bool {
        await MainActor.run { ClashViewModel.shared.addLog("[Privilege] 🔐 Installing sudoers configuration...") }

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let scriptPath = appSupport.appendingPathComponent("Ares/install_sudoers.sh")

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: scriptPath.deletingLastPathComponent(), withIntermediateDirectories: true)

        // Get current username
        let username = SudoersEscaper.user(NSUserName())

        // Path to active mihomo/clash-meta
        let clashPath = await CoreManager.shared.activeBinaryPath()
        guard FileManager.default.isExecutableFile(atPath: clashPath) else {
            await MainActor.run { ClashViewModel.shared.addLog("[Privilege] ❌ Clash binary not found") }
            return false
        }

        // Determine correct path for networksetup
        let networksetupPath = SudoersEscaper.commandPath("/usr/sbin/networksetup")
        let clashSudoersPath = SudoersEscaper.commandPath(clashPath)
        let lsofPath = SudoersEscaper.commandPath("/usr/sbin/lsof")

        let scriptContent = """
        #!/bin/bash

        SUDOERS_FILE="/etc/sudoers.d/ares_rules_v3"
        OLD_FILE="/etc/sudoers.d/ares_rules_v2"
        OLD_FILE_V1="/etc/sudoers.d/ares_rules"

        # Cleanup old files
        if [ -f "$OLD_FILE_V1" ]; then rm "$OLD_FILE_V1"; fi
        if [ -f "$OLD_FILE" ]; then rm "$OLD_FILE"; fi

        # Always overwrite to ensure paths are up to date
        if [ -f "$SUDOERS_FILE" ]; then
            rm "$SUDOERS_FILE"
        fi

        # Create sudoers content
        cat > "/tmp/ares_rules" <<'ARES_SUDOERS'
        # Ares Proxy Rules
        \(username) ALL=(root) NOPASSWD: \(networksetupPath)
        \(username) ALL=(root) NOPASSWD: \(clashSudoersPath)
        \(username) ALL=(root) NOPASSWD: \(lsofPath)
        ARES_SUDOERS

        # Validate before installing to avoid breaking sudoers include parsing
        /usr/sbin/visudo -cf "/tmp/ares_rules" >/dev/null

        # Move to /etc/sudoers.d (requires root)
        mv "/tmp/ares_rules" "$SUDOERS_FILE"
        chown root:wheel "$SUDOERS_FILE"
        chmod 440 "$SUDOERS_FILE"

        echo "Installation complete"
        """

        do {
            try scriptContent.write(to: scriptPath, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath.path)

            // Run installer with osascript (password prompt once)
            let escapedScriptPath = AppleScriptEscaper.stringLiteral(scriptPath.path)
            let script = """
            do shell script "'\(escapedScriptPath)'" with administrator privileges
            """

            guard let appleScript = NSAppleScript(source: script) else {
                return false
            }

            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)

            if let error = error {
                await MainActor.run { ClashViewModel.shared.addLog("[Privilege] ❌ Installation failed: \(error)") }
                return false
            }

            await MainActor.run { ClashViewModel.shared.addLog("[Privilege] ✅ Sudoers configuration installed successfully") }
            return true

        } catch {
            await MainActor.run { ClashViewModel.shared.addLog("[Privilege] ❌ Check failed: \(error)") }
            return false
        }
    }
}
