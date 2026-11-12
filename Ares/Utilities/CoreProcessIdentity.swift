import Foundation

/// A port number or executable name alone never establishes ownership.
nonisolated struct CoreProcessIdentity: Equatable {
    let pid: Int32
    let uid: UInt32
    let started: String
    let command: String

    init?(line: String) {
        let fields = line.split(maxSplits: 7, whereSeparator: { $0.isWhitespace })
        guard fields.count == 8, let pid = Int32(fields[0]), pid > 1,
              let uid = UInt32(fields[1]) else { return nil }
        self.pid = pid
        self.uid = uid
        started = fields[2...6].joined(separator: " ")
        command = String(fields[7]).trimmingCharacters(in: .whitespaces)
    }

    func belongsToAres(support: URL, userID: UInt32) -> Bool {
        guard uid == 0 || uid == userID else { return false }
        var invocation = command
        if invocation.hasPrefix("/usr/bin/sudo -n ") {
            invocation.removeFirst("/usr/bin/sudo -n ".count)
        }
        for directory in ["clash", "clash_user", "clash_root"] {
            let suffix = " -d " + support.appendingPathComponent(directory).path
            guard invocation.hasSuffix(suffix) else { continue }
            let binary = String(invocation.dropLast(suffix.count))
            return binary.hasPrefix("/") && !binary.contains(" -") &&
                (binary.hasSuffix("/Ares.app/Contents/Resources/clash-meta") ||
                 binary == support.appendingPathComponent("Core/mihomo").path)
        }
        return false
    }

    /// The privileged transaction validates the process again for each signal.
    static func terminationScript(_ processes: [(pid: Int32, snapshot: String)]) -> String {
        var commands = ["set -eu"]
        for process in processes where process.pid > 1 {
            commands.append("""
            matches() { [ "$(/bin/ps -ww -p \(process.pid) -o lstart=,command= 2>/dev/null || true)" = \(shellQuote(process.snapshot)) ]; }
            if matches; then
                /bin/kill -TERM \(process.pid) 2>/dev/null || true
                n=0
                while matches && [ "$n" -lt 30 ]; do /bin/sleep 0.1; n=$((n+1)); done
                if matches; then /bin/kill -KILL \(process.pid) 2>/dev/null || true; fi
            fi
            """)
        }
        return commands.joined(separator: "\n")
    }

    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
