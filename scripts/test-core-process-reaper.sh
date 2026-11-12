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
swiftc -parse-as-library "$ROOT/Ares/Utilities/CoreProcessIdentity.swift" \
 "$ROOT/Ares/Utilities/ProcessManager.swift" "$ROOT/Ares/Utilities/AppleScriptEscaper.swift" \
 "$ROOT/Ares/Services/CoreProcessReaper.swift" "$OUT/main.swift" -o "$OUT/test"
"$OUT/test" "$OUT"
