Ares 1.0.3 fixes the empty Proxies page after importing a subscription while the core is stopped.

The previous fix preserved the subscription configuration but still loaded the page exclusively from the running core. Saved subscriptions now supply their node and group lists directly, without starting the core.

- Browse and search saved nodes in Rule and Global views while disconnected.
- Refresh local lists after subscription selection, update or edit; keep local metadata separate from runtime state.
- Enable node switching and latency testing only when live core data is available.
- Parse block/flow YAML, quoted names, anchors and JSON with a pinned YAML parser. Provider-only subscriptions explicitly indicate that provider nodes require the core.

**Update:** use the built-in update check or the arm64 DMG. Your saved subscription is retained; no reimport or core startup is needed to view embedded nodes.

**Validation:** arm64 build; 60 standalone regression tests; 6 portable subscription parser tests plus a local read-only acceptance test confirming 32 VLESS nodes and 2 groups; 6 appcast tests. The actual ProxiesView was exercised in a separate executable with inert services, confirming stopped-core lists, search, Global view and disabled runtime actions. Live proxy connectivity and production update installation were not exercised on the development host.

**Requirements:** Apple Silicon Mac, macOS 14 or later. Packages use ad-hoc code signing and Ed25519 update signatures; they are not Apple-notarized. Intel is unsupported.

Ares is MIT licensed. The bundled mihomo core is GPLv3; matching source and license accompany the release. Sparkle and Yams retain their upstream licenses, included with the app.
