# Ares 1.0.13

This release reorganizes the workspace so application routing, network quality, policies and scenes are directly accessible. Requires macOS 14 or later on Apple Silicon. Includes mihomo v1.19.34; Intel Macs are not supported.

- Added Applications, Network Quality, Policies and Scenes as independent sidebar pages. Overview and monitoring, routing, subscriptions and tools now have distinct navigation groups.
- Reworked Dashboard with compact, side-by-side upload and download charts. Activity and network-quality summaries occupy the freed space, with direct links to detailed pages.
- Dashboard activity totals include all current non-Ares connections. The three busiest sources are explicitly labeled as a subset; sources group applications, executables and unidentified source addresses. Unavailable runtime data displays a dash instead of a fabricated value.
- Replaced Dashboard switches with compact On / Off controls and a shared raised surface. Rule, Global and Direct use a horizontal icon-and-label selector with visible connecting lines. Both appearances and Reduce Motion are supported.
- Made recommended policies directly discoverable on the Policies page. The recommendation opens as a reviewable draft; configuration changes still require Apply.
- Adapted existing application-routing, quality and scene views for independent pages, retaining scrolling with hidden scrollbars and existing validation, undo and runtime guards.

Network-quality monitoring remains opt-in. Its Dashboard success rate describes Google probe samples, not all application traffic. This update does not automatically enable TUN, system proxy or monitoring.

Validated with isolated regression tests, native light/dark UI previews and an arm64 production build. Release packaging additionally validates the bundled core with isolated loopback tests. Live TUN/network changes and installed-app upgrade/relaunch remain device acceptance checks.

Update archives use Sparkle Ed25519 signatures. The app is ad-hoc signed and is not Apple-notarized.
