import Foundation
import AppKit

/// Service to handle privilege escalation via sudoers
class PrivilegeService {
    static let shared = PrivilegeService()
    
    private init() {}
    
    /// Check if we have password-less sudo access (Async)
    func checkPrivileges() async -> Bool {
        // Run blocking checks on background thread
        return await Task.detached(priority: .userInitiated) {
            // checking "true" will fail because we didn't whitelist /usr/bin/true
            guard let clashPath = Bundle.main.path(forResource: "clash-meta", ofType: nil) else {
                return false
            }
            
            let pkillPath = "/usr/bin/pkill"
            
            // Check 1: Clash Binary
            let t1 = Process()
            t1.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
            t1.arguments = ["-n", clashPath, "-v"]
            // redirect output to null to keep logs clean
            t1.standardOutput = Pipe()
            t1.standardError = Pipe()
            try? t1.run()
            t1.waitUntilExit()
            if t1.terminationStatus != 0 { return false }
            
            // Check 2: Pkill (Test with safe argument)
            // Note: sudo -n returns 1 if password needed. pkill returns 1 if no match found.
            // We MUST distinguish between these two "1"s.
            let t2 = Process()
            t2.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
            t2.arguments = ["-n", pkillPath, "-f", "ares_dummy_process_check_12345"]
            
            let pipeErr = Pipe()
            t2.standardError = pipeErr
            t2.standardOutput = Pipe() // Silence stdout
            
            try? t2.run()
            t2.waitUntilExit()
            
            let errData = pipeErr.fileHandleForReading.readDataToEndOfFile()
            if let errStr = String(data: errData, encoding: .utf8)?.lowercased() {
                 // Sudo error messages usually contain "password" or "sorry"
                 if errStr.contains("password") || errStr.contains("sorry") {
                     return false
                 }
            }
            
            
            // Check 3: LSOF (Critical for port checking)
            // If this fails (return 1 and "password" in stderr), we must reinstall sudoers.
            let t3 = Process()
            t3.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
            // lsof -v is safe and fast
            t3.arguments = ["-n", "/usr/sbin/lsof", "-v"]
            
            let pipeErr3 = Pipe()
            t3.standardError = pipeErr3
            t3.standardOutput = Pipe() // Silence stdout
            
            try? t3.run()
            t3.waitUntilExit()
            
            let errData3 = pipeErr3.fileHandleForReading.readDataToEndOfFile()
            if let errStr = String(data: errData3, encoding: .utf8)?.lowercased() {
                 if errStr.contains("password") || errStr.contains("sorry") {
                     return false
                 }
            }
            
            // If we got here, sudo didn't complain about password.
            return true
        }.value
    }
    
    /// Install sudoers configuration
    func installSudoers() async -> Bool {
        await MainActor.run { ClashViewModel.shared.addLog("[Privilege] 🔐 Installing sudoers configuration...") }
        
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let scriptPath = appSupport.appendingPathComponent("Ares/install_sudoers.sh")
        
        // Ensure directory exists
        try? FileManager.default.createDirectory(at: scriptPath.deletingLastPathComponent(), withIntermediateDirectories: true)
        
        // Get current username
        let username = NSUserName()
        
        // Path to clash-meta
        guard let clashPath = Bundle.main.path(forResource: "clash-meta", ofType: nil) else {
            await MainActor.run { ClashViewModel.shared.addLog("[Privilege] ❌ Clash binary not found") }
            return false
        }
        
        // Determine correct path for networksetup
        let networksetupPath = "/usr/sbin/networksetup"
        let pkillPath = "/usr/bin/pkill"
        let lsofPath = "/usr/sbin/lsof"
        
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
        echo "# Ares Proxy Rules" > "/tmp/ares_rules"
        echo "\(username) ALL=(root) NOPASSWD: \(networksetupPath)" >> "/tmp/ares_rules"
        echo "\(username) ALL=(root) NOPASSWD: \(clashPath)" >> "/tmp/ares_rules"
        echo "\(username) ALL=(root) NOPASSWD: /bin/kill" >> "/tmp/ares_rules"
        echo "\(username) ALL=(root) NOPASSWD: \(pkillPath)" >> "/tmp/ares_rules"
        echo "\(username) ALL=(root) NOPASSWD: \(lsofPath)" >> "/tmp/ares_rules"
        
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
            let script = """
            do shell script "'\(scriptPath.path)'" with administrator privileges
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
