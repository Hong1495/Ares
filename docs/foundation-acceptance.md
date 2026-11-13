# Configuration and runtime foundation acceptance

Date: 2026-11-13. Core contract: mihomo v1.19.34. Target: macOS arm64.

## Implemented boundary

- Structured configuration merge; inherited/local/runtime field ownership; no forced group interval.
- Source-to-saved structural diff, setting ownership controls, pending changes, allowlisted runtime readback.
- Shared ConfigurationCoordinator for settings, profile replacement, TUN replacement and restart.
- Prepare/validate before stop; confirmed stop before replacement; failed candidate cleanup before rollback.
- Rollback uses a captured runtime configuration and selections, rather than re-reading the updated subscription.
- Critical listener/mode/TUN fields must match the startup API response before readiness.
- Last verified configurations persist per mode, atomically, in a 0700 directory with 0600 files.
- Explicit recovery requires matching subscription identity and target mode. Subscription contents/preferences are not overwritten by recovery.
- Recovered older profile revision remains distinct: selecting nodes requires applying the current revision again.
- System proxy and MITM upstream use verified runtime ports. Successful coordinated activation is checkpointed after dependent routing succeeds.
- Sleep suspends monitoring; wake verifies the existing core with bounded retries, without launching a replacement.
- Instance-scoped unexpected-exit callbacks invalidate readiness and attempt system proxy restoration; no blind relaunch.
- Shutdown keeps the operation gate through handoff; repeated successful cleanup is idempotent, failed cleanup releases it for retry.
- Aborted update preparation invalidates the pending installer callback. No baseline means no proxy authorization or mutation.
- Startup does not request unused privileges when both TUN and system proxy are off.

## Automated acceptance

| Layer | Result | Limitation |
|---|---|---|
| Pure functions/file transactions/checkpoints | 122 tests passed | Temporary preference suites and files only |
| YAML package | 27 passed, 1 optional fixture skipped | Synthetic inputs |
| Production coordinator + inert services (including explicit recovery and local-rule apply) | Passed | No real OS privilege calls |
| Production sleep/wake logic + inert controller | Passed | Does not suspend the computer |
| Configuration/proxy fake HTTP harnesses | Passed | Includes stale generation, failures and selection readback |
| Process reaper/helper harness | Passed | Owned test children; unrelated process survives |
| Python release scripts | 8 passed | Does not publish a release |
| Native macOS arm64 mihomo | Passed | Dynamic loopback ports, no system proxy or TUN |
| Dedicated Linux arm64 VM | Passed | Normal/TUN/normal, actual HTTP/SOCKS/TUN flow, invalid reload, crash/restart, exit cleanup |
| Release build | Passed | Built app not installed/launched on production network |

Native test command: `python3 scripts/test-native-core.py /path/to/pinned/clash-meta`.
VM uses `scripts/fixtures/core-flow-vm.py`; fixture generation uses `ARES_FLOW_FIXTURE_DIR` with `scripts/test-effective-config.sh`. The fixture runner rejects hosts other than the dedicated Linux VM. Tests do not consume user subscriptions.

## Release gate still open

This is an implementation and isolated acceptance checkpoint, not a claim that the entire foundation release is production-accepted.

- Real macOS TUN privilege grant/denial and interface lifecycle on an isolated macOS host.
- System proxy restore across multiple network services, network switching and sleep/wake.
- Full signed updater install/relaunch with the new lifecycle, not only the tested shutdown transition and Sparkle callback guards.
- Manual macOS settings/recovery flow using the actual app in an isolated user environment.
- Persistent snapshot is the last verified launch for each mode, not a complete history or an embedded copy of provider/Geo resources. Resource availability is revalidated on recovery.
- Critical startup readback covers the API contract, not every DNS/rule/provider semantic.

Do not publish or replace the user's working app based on Linux TUN tests alone. A formal privileged helper migration remains a separate architectural project; this patch retains the existing privilege mechanism.

## Rule-stage acceptance included in this checkpoint

- Real `/rules` decoding uses ordered indices and optional `extra.hitCount`; malformed replies and HTTP failures fail visibly.
- Rule-set HTTP update, metadata readback and actual matching traffic passed on the isolated native core. Resource fixture is initialized before traffic; API readiness alone does not imply remote resources are ready.
- Rule editor applies through the production coordinator tested with inert services and a temporary defaults suite. Validation, activation, cleanup and stale-revision failures retain previous preferences.
- Actual Rules/Rule Sets/editor views compiled with inert service and storage mocks: table, provider references, initial draft load and error retention inspected. No production app launched.
- Graphical per-rule editing/reordering and full nested source mapping are pending; current local editor remains textual.

## Rule editor follow-up

Local rules now support form/list edits and explicit up/down ordering, with lossless source fallback. Verified rule-source snapshots include all sub-rule sections and nested RULE-SET references; remote provider payload contents are not fetched or expanded. Snapshot inspection is not runtime hit evidence. New package total: 33 passed, 1 optional skipped. Native core tests additionally verify first-match ordering and SUB-RULE execution. Narrow list/source headers visually checked after hiding the redundant Editor label.

## Policy/resource stage acceptance

- 127 pure/file tests passed; package 37 passed, 1 optional skipped.
- Production policy apply service tested with inert services and a private defaults suite: commit, preparation/activation/cleanup failure, stopped-core validation and stale editor rejection.
- Actual parameter overlays pass generated normal/TUN core configuration validation.
- Fake resource transport covers encoded names, GET/PUT paths, 503 rejection, readback, old app delay invalidation and generation races.
- Native loopback core covers all four group types, nested selection, URLTest/Fallback pin/reset, load-balanced real flow, HTTP provider refresh, new-member selection and health measurements.
- Existing groups can edit selected parameters; creation/deletion and general dependency rewiring are not included. The UI's dependency table is runtime membership, not a network route.
- Release build and inert native previews verified. No production installation or network switch performed.

## DNS-stage acceptance

- 127 safe tests passed; package 42 passed, 1 optional skipped. arm64 Release build passed.
- Advanced DNS fields use subscription-scoped staged overlays, full-field replacement and explicit inheritance. Application-owned DNS fields are excluded. Overlay runs after default inheritance so adding one advanced field cannot suppress the app's default DNS block.
- Configuration coordinator harness covers DNS commit, prepare failure, activation/cleanup rollback, stale overrides and offline validation. Normal/TUN generated files pass pinned-core validation.
- Fake DNS HTTP transport verifies records/TTL, NXDOMAIN versus empty success, invalid names, malformed/HTTP failures, runtime generation and endpoint races.
- `scripts/test-native-dns.py /path/to/pinned/clash-meta` uses an owned core, four loopback UDP resolvers and an HTTP origin. A/AAAA, TTL, domain policies, NXDOMAIN and empty success pass. Actual direct HTTP flow resolves through direct-nameserver; HTTP proxy hostname resolves through proxy-server-nameserver. Host network settings are untouched and listener cleanup is checked.
- Query timings are API round trips measured by Ares, not upstream-only latency. The API does not expose upstream provenance, hosts/Fake IP assignment or complete resolver decision trace.
- Actual DNS UI compiled with inert mocks; compact 740×540 content, override/pending behavior, query results, invalid inputs and stale-result removal inspected. This does not substitute for the open macOS production acceptance gate above.

## Egress/listener stage acceptance

- Subscription-scoped static-node dialer/interface overrides, global interface, HTTP/SOCKS/Mixed single-port listeners and TCP/UDP forwarding are staged through the shared configuration transaction. Inherited unknown fields stay intact; removed-node drafts remain editable and cannot apply silently.
- Static node/group dependency cycles, target references, invalid addresses/ports and overlapping supported sockets fail validation. Provider-expanded dependency graphs and arbitrary inherited listener types/ranges are not fully covered by the app's static checks.
- `scripts/test-listener-verification.sh /path/to/pinned/clash-meta` validates the production ownership checker against real owned core sockets. Fake socket listings reject different PIDs, transports, bind addresses and outbound connections. The normal CI variant runs pure checks without launching a core.
- `scripts/test-native-egress.py` verifies a real two-hop HTTP proxy chain; HTTP auth 407/success; per-listener DIRECT routing; SOCKS TCP and UDP; fixed TCP and UDP forwarding. All upstreams, origins and listeners use loopback and are cleaned up afterward.
- Global interface readback participates in startup verification. Available-interface checks and configuration validation do not replace real macOS multi-interface routing tests; loopback tests do not prove physical interface pinning.
- Supported additional listeners must share their owner PID with the API socket before startup becomes successful. Root socket visibility may depend on existing noninteractive authorization; full TUN privilege/ownership acceptance remains open.
- 127 safe tests and 49 package tests passed (1 optional skipped); coordinator scenarios and normal/TUN core validation passed. Release build and inert 740×560 UI preview checked. No production install or network switch.

## Diagnostics/manual-scenes acceptance

- 131 safe tests passed, package 49 passed / 1 optional skipped. Private scenario storage covers round-trip, absent/empty values, unrelated-profile preservation, duplicate names, corrupt schema, atomic retention and 0700/0600 permissions.
- Production scenario service exercised with inert lifecycle services: multi-section apply/undo, prepare/activation/cleanup failures, stale review, different profile, stopped validation, and undo invalidation after later edits or subscription revision changes.
- Production diagnostics service exercised with inert read APIs: selected/running revision mismatch, saved/verified/readback comparisons, historical versus unknown measurements, partial provider errors, stale generation and stopped runtime. No health probes are implied by a successful snapshot.
- Effective-config harness composes scene preferences through production policy/DNS/egress parsers and restores missing keys. Existing normal/TUN candidates pass pinned core validation. Actual macOS TUN, physical interfaces and signed updater gates remain open.
- Actual scene and diagnostic views compiled with mocks, then inspected at compact sizes; review reports affected sections without raw credentials. Runtime evidence has a selection detail area for long text. Release build passed without launching the production app.
- Scope: current-subscription snapshots of local rules/DNS/policy/egress overrides; local rules remain global. Basic settings, subscription switching, node selection and proxy/TUN mode are not part of this first manual scene version. Undo lasts only the current process session and requires the unchanged applied preference baseline.

## 1.0.10 upgrade-test release decision

The user explicitly requested acceptance, commit and publication of a new version for an installed-app upgrade test on 2026-11-13. Version 1.0.10 publishes this implementation checkpoint after the automated/isolated acceptance suite passes. The open real-macOS and signed install/relaunch items above remain user acceptance items, not completed claims. Release packaging now runs the full lifecycle/configuration/diagnostics harnesses and the bundled v1.19.34 core's native loopback tests before publication. The release notes disclose these limits; the working installed app is left unchanged for the user's Sparkle upgrade test.

## Scene editor and scroll presentation follow-up

- Independent scene drafts edit rules and typed YAML projections of DNS/policy/routing overrides. Saving changes only the private scene library; runtime semantic validation remains in Review/Apply. Unedited sections retain exact stored strings, missing values stay missing, and existing schema-1 scenes decode without the optional update timestamp.
- Storage and production service harnesses reject stale scene replacement, changed preference/subscription baselines, duplicate names, and reviewed scenes that have since changed. Scene save does not call lifecycle services or mutate live preferences. Runtime checkpoint capture is followed by a second scene freshness check.
- Removed policy group targets fail candidate generation instead of silently dropping scene intent. Projection tests preserve explicit empty strings/lists, boolean types, listener credentials and unknown nested listener fields; invalid/duplicate/unknown top-level input fails visibly.
- 133 safe tests passed; package 54 passed / 1 optional skipped; coordinator and effective-config harnesses passed. Synthetic normal/TUN configs passed pinned mihomo v1.19.34 `-t`; arm64 Release built successfully.
- All app scene roots use `scrollIndicators(.never, axes: [.horizontal, .vertical])`, with local overrides consistently using never. Isolated real-view previews verified scrolling in topology (80 targets), native Table (40 scenes), and TextEditor (80 rules) without visible scrollbars. Production app/core/system network untouched.
- Remaining scene work: node selections and routing mode in the transaction, then environment condition evaluation and automatic triggers. No automatic network changes or release performed in this follow-up.

## Scene routing and automatic execution checkpoint

- Scenes now optionally carry proxy mode and saved node choices. Legacy scenes keep current routing values. Explicit choices require selectable groups, existing members and API confirmation; failure restores preference state and the captured runtime. Recovery checkpoints now capture actual manual choices from the core. Offline scene choices are strictly checked when the core next starts, including dynamic provider members.
- Shared coordinator adds checks before stopping the previous runtime and before checkpointing the activated runtime; scene verification occurs before restoring system proxy. Late network/scene invalidation triggers rollback. Undo restores an originally absent mode preference rather than materializing a default.
- Network matching uses NWPathMonitor facts, explicit conjunction conditions, priority and tie rejection. No SSID, trusted network identity or physical route inference. The production automation service is opt-in, current-profile-only, idle-ready-core-only, with 10-second debounce and 30-second attempt cooldown. Failures/sleep/manual scene-node-mode changes pause; pause persists. Changed subscription revision blocks automatic use of old scenes.
- 138 safe tests passed; package 54 passed / 1 optional skipped. Production automation harness verifies gates, conflicts, idempotence, failure latch, environment races, subscription changes and persistent pause. Coordinator harness covers routing rollback/undo and pre-stop/post-activation invalidation. Lifecycle/API/diagnostic harnesses passed.
- Pinned v1.19.34 synthetic normal/TUN validation passed. Native loopback suite verifies Rule/Global/Direct readback, GLOBAL selection and real flow in addition to existing group/provider/recovery checks. A stale local v1.19.27 binary was rejected by the native harness version assertion; tests were rerun with the verified 1.0.10 release's v1.19.34 binary.
- Inert native previews checked routing and environment editors plus automatic match preview. Release arm64 build passed; no installed app replacement, publication, host system proxy/TUN changes, or physical network switching. Real macOS privileges, sleep/network changes and signed update gates remain open.

## 1.0.11 scene catalog, history and migration acceptance

- Static group/member selection is available offline; a matching live runtime includes provider members. HTTP failure and stale generation/revision reject catalog responses. No subscription credentials are projected into the catalog.
- Successful running-core apply alone approves a changed subscription revision for automatic scenes. Offline save, failed apply and later configuration edits remain gated. Original scene identity/source revision stay intact.
- History stores the latest 100 attempt summaries with trigger/outcome/section names. Corrupt history is preserved; filesystem permissions and retention are tested. Production history is never used by the isolated coordinator harness.
- Full local verification passed: 139 safe tests, 54 package tests passed with one optional skip, coordinator/automation/catalog/lifecycle/API/diagnostic/reaper/listener tests, Python update tests, isolated previews and Debug build. Release arm64 build also passed. Release CI additionally executes native egress validation against the bundled pinned core.
- UI acceptance checked native scene group/member pickers, missing-choice messaging and execution history. Installed production application and host proxy/TUN are left untouched. Physical-network and installed-update/relaunch acceptance remain explicit limits, not assumed successes.
