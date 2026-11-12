#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d /tmp/ares-reaper-test.XXXXXX)"
trap 'rm -rf "$OUT"' EXIT
mkdir -p "$OUT/Ares.app/Contents/Resources" "$OUT/Ares/clash_user"
cat > "$OUT/fake.c" <<'C'
#include <signal.h>
#include <unistd.h>
int main(void) { signal(SIGTERM, SIG_IGN); while(1) pause(); }
C
cc "$OUT/fake.c" -o "$OUT/Ares.app/Contents/Resources/clash-meta"
cat > "$OUT/main.swift" <<'SWIFT'
import Foundation
import Darwin
final class PrivilegeService: @unchecked Sendable {
    static let shared = PrivilegeService()
    func installSudoers() async -> Bool { fatalError("Tests must never request administrator access") }
}
@main struct ReaperTest {
    enum Failure: Error { case assertion }
    static func check(_ value: Bool) throws { if !value { throw Failure.assertion } }
    static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let binary = root.appendingPathComponent("Ares.app/Contents/Resources/clash-meta")
        let support = root.appendingPathComponent("Ares")
        let child = Process()
        child.executableURL = binary
        child.arguments = ["-d", support.appendingPathComponent("clash_user").path]
        try child.run()
        let unrelated = Process()
        unrelated.executableURL = binary
        unrelated.arguments = ["-d", root.appendingPathComponent("unrelated").path]
        try unrelated.run()
        defer {
            if child.isRunning { kill(child.processIdentifier, SIGKILL) }
            if unrelated.isRunning { kill(unrelated.processIdentifier, SIGKILL) }
        }
        try await Task.sleep(for: .milliseconds(200))
        let reaper = CoreProcessReaper(support: support)
        let identities = try await reaper.ownedProcesses()
        try check(identities.count == 1 && identities[0].pid == child.processIdentifier)
        // No retained Process is supplied: exercises recovery after losing the owner handle.
        let success = await reaper.reap()
        try check(success)
        try check(unrelated.isRunning)
        child.waitUntilExit()
        try check(child.terminationStatus == SIGKILL)
        let helperChild = Process()
        helperChild.executableURL = binary
        helperChild.arguments = ["-d", support.appendingPathComponent("clash_user").path]
        try helperChild.run()
        defer { if helperChild.isRunning { kill(helperChild.processIdentifier, SIGKILL) } }
        let helperFile = root.appendingPathComponent("stop-helper")
        try CoreStopHelper.script(support: support, userID: getuid()).write(to: helperFile, atomically: true, encoding: .utf8)
        func helper(_ args: [String], user: String) throws -> Int32 {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = [helperFile.path] + args
            process.environment = ["SUDO_UID": user, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
            try process.run(); process.waitUntilExit()
            return process.terminationStatus
        }
        try check(helper([], user: "999999") == 77)
        try check(helper([String(unrelated.processIdentifier)], user: String(getuid())) == 64)
        try check(helperChild.isRunning && unrelated.isRunning)
        try check(helper([], user: String(getuid())) == 0)
        helperChild.waitUntilExit()
        try check(!helperChild.isRunning && unrelated.isRunning)
        print("PASS: fixed helper stops only owned child, rejects arguments and wrong caller")
        let second = await reaper.reap()
        try check(second)
        // Exercise the same shell transaction used for root processes, as this user,
        // against only the retained fake child. No authorization or production core.
        let runner = ProcessManager()
        let wrong = CoreProcessIdentity.terminationScript([(unrelated.processIdentifier, "stale identity")])
        _ = try await runner.run(executable: "/bin/sh", arguments: ["-c", wrong])
        try check(unrelated.isRunning)
        let snapshot = try await runner.run(executable: "/bin/ps", arguments: ["-p", String(unrelated.processIdentifier), "-o", "lstart=,command="])
        let script = CoreProcessIdentity.terminationScript([(unrelated.processIdentifier, snapshot.output.trimmingCharacters(in: .newlines))])
        let result = try await runner.run(executable: "/bin/sh", arguments: ["-c", script], timeout: 10)
        try check(result.exitCode == 0)
        unrelated.waitUntilExit()
        try check(unrelated.terminationStatus == SIGKILL)
        print("PASS: privileged transaction logic and stale identity rejection")
        print("PASS: stale recovery, TERM timeout → KILL, exit confirmation, unrelated process survives, repeated stop")
    }
}
SWIFT
swiftc -parse-as-library "$ROOT/Ares/Utilities/CoreProcessIdentity.swift" "$ROOT/Ares/Utilities/CoreStopHelper.swift" \
 "$ROOT/Ares/Utilities/ProcessManager.swift" "$ROOT/Ares/Utilities/AppleScriptEscaper.swift" \
 "$ROOT/Ares/Services/CoreProcessReaper.swift" "$OUT/main.swift" -o "$OUT/test"
"$OUT/test" "$OUT"
