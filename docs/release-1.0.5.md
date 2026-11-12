Ares 1.0.5 connects saved subscriptions and node choices to verified proxy startup and TUN transitions.

- Choose a manual node while the core is stopped; the choice is saved per subscription and restored on startup, normal/TUN restart, and subscription switching.
- Confirm node selection with a core read-back before reporting success.
- Make Rule / Global / Direct change the actual core mode, and persist the mode while stopped.
- Start TUN from a stopped state, confirm the active TUN setting, and restore the previous state if startup fails.
- Prevent System Proxy from being enabled or restored until the core and selected subscription are ready.
- Keep selected subscription nodes separate from stale nodes left by a previous running configuration.

**Update:** use the built-in update check or download the arm64 DMG. Saved subscriptions are retained. While stopped, select a node in the Proxies page; then start the core, enable System Proxy, or enable TUN from Dashboard.

**Validation:** arm64 Release build; 66 isolated XCTest checks, 6 portable YAML subscription parser tests and 6 appcast tests. In an isolated Linux ARM64 VM, the supplied real subscription loaded 51 nodes; 35 were latency-testable on the final run. Two nodes were switched and read back successfully. Rule and Global mode, HTTP and SOCKS proxy traffic, direct TUN-captured traffic, and the normal → TUN → normal cycle all returned HTTPS 204. macOS networksetup, authorization prompts and restoration of the host's previous proxy state were not exercised; test those on the installed Mac and stop if the connection does not recover.

**Requirements:** Apple Silicon Mac, macOS 14 or later. Packages use ad-hoc code signing and Ed25519 update signatures; they are not Apple-notarized. Intel is unsupported.

Ares is MIT licensed. The bundled mihomo core is GPLv3; matching source and license accompany the release. Sparkle and Yams retain their upstream licenses, included with the app.
