# Ares process lifecycle repair

The installed host's TCP 127.0.0.1:7890 listener was confirmed by read-only privileged lsof to be PID 5179, a root clash-meta launched by an older Ares Debug bundle on November 11. Its sudo parent (5178) had been reparented to launchd. The production processes were not stopped during development tests.

The 1.0.5 lifecycle only retained an in-memory Process. Startup detected occupied ports but could not reclaim old Ares children; quit could report success with no Process even when old children remained. Repeated quit requests could bypass asynchronous cleanup.

The repair identifies Ares core invocations by user/root UID, exact Ares configuration directory, supported Ares executable location, PID and start time. It reclaims legacy cores and sudo wrappers before checking ports and during shutdown, with TERM, bounded wait, KILL, and final process scan. System proxy snapshots are restored before startup recovery; ordinary shutdown retains its restore-before-stop ordering. Port occupants from other clients remain conflicts, not signal targets. Privileged cleanup uses a macOS authorization transaction which rechecks identity before signals; cancellation fails cleanup explicitly. No broad kill permission is added to sudoers.

Shutdown blocks new UI transitions, waits for in-flight work to settle, and repeated quit requests wait for the existing cleanup rather than terminating immediately.

Reference reviewed: Clash Verge Rev dev branch, `src-tauri/src/core/manager/lifecycle.rs` (serialized controlled stop and proxy clearing) and `state.rs` (child termination and bounded exit wait):
- https://github.com/clash-verge-rev/clash-verge-rev/blob/dev/src-tauri/src/core/manager/lifecycle.rs
- https://github.com/clash-verge-rev/clash-verge-rev/blob/dev/src-tauri/src/core/manager/state.rs

Validation: arm64 Release build; 72 standalone tests; six portable YAML tests. `scripts/test-core-process-reaper.sh` compiles inert fake children, verifies lost-owner recovery, TERM-resistant child escalation to KILL, unrelated-process survival, repeat cleanup, privileged shell transaction logic as an unprivileged test user, and stale identity rejection. It never starts a proxy, requests authorization, or changes host networking.

Limitations: the root authorization dialog and real TUN route teardown still require installed-Mac acceptance. This is recovery on normal quit/restart, not a launchd supervisor that guarantees child removal after SIGKILL of the app. Ares's existing sudo-based TUN launch remains; replacing it with a privileged helper is a separate architectural change.
