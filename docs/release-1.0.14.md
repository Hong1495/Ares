# Ares 1.0.14

This release refines Dashboard and brings the new routing and monitoring pages into the shared workspace design. Requires macOS 14 or later on Apple Silicon. Includes mihomo v1.19.34; Intel Macs are not supported.

- Reorganized Dashboard into two independently flowing columns, removing stretched blank areas. Applications follows Activity; Policies and Scenes follow Network Quality.
- Expanded Dashboard summaries with application rules, policy-type counts and saved scenes. Configuration summaries refresh while the page is active and reload when the subscription changes. Limited rule and scene lists explicitly indicate their scope.
- Activity now lists every current non-Ares source in a scrollable region, with connection counts and relative shares. No sources are omitted from totals.
- Network Quality shows each HTTPS/DNS target's success rate, latest measured latency and recent sample history. Failed samples appear as gaps with failure markers; unavailable results remain dashes.
- Removed the separate Reachability section and its independent periodic probes. Dashboard reuses Network Quality measurements; monitoring remains opt-in.
- Unified Applications, Network Quality, Policies, Scenes and related editors with left-aligned controls, consistent toolbars, concise English labels and hidden scrollbars. Detailed guidance remains available through help and tooltips.

This update does not automatically enable TUN, system proxy, monitoring or scene automation. Validation covers isolated regression tests, native Dashboard preview and production compilation. Release packaging also checks the bundled core using isolated loopback tests; live network changes and installed-app upgrade/relaunch remain device acceptance checks.

Update archives use Sparkle Ed25519 signatures. The app is ad-hoc signed and is not Apple-notarized.
