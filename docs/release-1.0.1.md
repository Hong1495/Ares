Ares 1.0.1 fixes subscriptions that download successfully but cannot populate the node list.

- Preserve node ports and nested provider settings when merging subscriptions with app settings.
- Preserve complete geodata URL sections instead of leaving invalid YAML behind.
- Validate a candidate configuration before replacing the previous working configuration.
- Load nodes even before their first latency measurement, refresh when opening Proxies, and expand groups initially.
- Allow reapplying the selected profile while the core is running. Clarify when a saved subscription is waiting for the core to start.

**Update:** use the built-in update check in Ares 1.0.0, or download the DMG for your Mac. Your saved subscription remains available. If the core is stopped, start it from Overview when ready; if already running, use **Apply again** in Profiles.

**Validation:** Debug compilation, 60 standalone XCTest checks and 6 appcast tests. A read-only check against the affected local subscription confirmed that all 32 node ports, node/group definitions and geodata URLs survive the merge. No production application or core was launched on the development host. Live core connectivity and in-place update installation remain to be verified in an isolated environment.

**Requirements:** macOS 14 or later. Apple Silicon and Intel downloads are provided. Packages are ad-hoc code signed and Ed25519 signed for updates; they are not Apple-notarized.

The bundled mihomo core is GPLv3. Its exact upstream source archive, license and release metadata accompany these downloads. Ares source is MIT licensed; Sparkle retains its upstream license.
