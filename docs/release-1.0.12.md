# Ares 1.0.12

This release adds application routing, continuous network-quality measurements, recommended policies and visual network configuration. Requires macOS 14 or later on Apple Silicon. Includes mihomo v1.19.34; Intel Macs are not supported.

- Open Application Routing from Activity or a connection's context menu. Assign exact executable paths to Direct, Block or a policy; remove local overrides and undo the last edit. Inspect rule precedence and core-reported connections, matched rules, routes and traffic. Helpers are separate executables; local rules apply across subscriptions and require Rule mode.
- Open Network Quality from Activity or Proxies. Opt in to periodic HTTPS probes through a selected policy and DNS API measurements, with success rate, median, P95, variation and a bounded sample chart. Observe route changes, choose a member manually or resume core automatic selection. Monitoring continues with the window closed and pauses for sleep, stopped cores and network operations.
- Add recommended automatic, fallback and manual groups from Compose Policies. Recommendations preserve subscription groups and rules, support provider members, and stay in a draft until Apply. Assign the new groups in application or routing rules to use them. Default checks run every five minutes with a five-second timeout and 50 ms automatic-selection tolerance.
- Compose policy groups and local rules in one validated transaction: create, delete, restore inheritance, reorder members, nest groups and reference node resources. Invalid references and cycles prevent activation; failed activation restores previous settings and runtime.
- Edit common DNS mappings, resolver/filter lists, HTTP/SOCKS/Mixed listeners and TCP/UDP forwarding through forms. Source editing remains available for advanced values, with authentication, TLS and unknown fields preserved.
- Connect runtime diagnostics to configuration evidence and resource sources. Inspect bounded resource-operation history with request/readback stages and unconfirmed failures. Stale drafts and responses cannot overwrite newer configuration or runtime evidence.

Quality measurements describe the listed probe targets, not all application traffic. DNS API duration may include cached results. Route changes are sampled every ten seconds; intermediate switches may be missed and automatic-switch causes are not exposed by the core API. Load-balanced routes are not presented as a single exit.

Validation includes 139 safe tests, 66 package tests with one optional skip, production-service isolation tests, native UI previews and arm64 Debug/Release builds. Real loopback mihomo tests verify primary failure to backup, primary recovery, manual pin and automatic resume, policy traffic, DNS and TCP/UDP forwarding. The unprivileged macOS fixture cannot resolve executable identity: actual process-specific routing under privileged/TUN operation remains an explicit real-device acceptance item. Installed-app upgrade/relaunch, production sleep/wake and physical network changes also remain real-device acceptance items.

Update archives use Sparkle Ed25519 signatures. The app is ad-hoc signed and is not Apple-notarized.
