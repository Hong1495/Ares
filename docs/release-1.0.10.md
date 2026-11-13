# Ares 1.0.10

This release expands mihomo configuration support and adds configuration recovery, runtime diagnostics and manual scenes. Requires macOS 14 or later on Apple Silicon. Intel Macs are not supported.

- Preserves subscription DNS, TUN, sniffing, provider and unknown configuration fields. Settings distinguish inherited values from local overrides, validate candidates before activation, and restore the previous configuration after a failed switch.
- Adds editable local rules and ordering, rule-source inspection, rule-provider updates, policy-group parameters and node-resource health measurements.
- Adds advanced DNS configuration and real core DNS queries with records, TTL and response status. Historical latency and API round-trip measurements are labeled separately.
- Adds per-node proxy chaining and outbound interfaces, HTTP/SOCKS/Mixed listeners and TCP/UDP forwarding. Validates static references, cycles and port conflicts, and checks supported listener socket ownership after startup.
- Adds Activity Diagnostics for configuration differences, policy membership and resource metadata. Partial read failures remain visible instead of appearing as healthy results.
- Adds manual Scenes for the current subscription’s local rules, DNS, policy and routing overrides, with change review and session-local undo. Scenes do not change node selections, basic network settings or proxy/TUN switches.
- Improves core transition recovery, sleep/wake checks, exit cleanup and update handoff. An aborted update cannot invoke an obsolete install callback.

Advanced DNS/listener sections currently use YAML editors. Resource measurements are historical snapshots; diagnostics do not claim to expose a physical network route or a complete DNS decision trace.

Validated with isolated configuration/transaction tests, native loopback proxy chains, HTTP authentication, SOCKS TCP/UDP, DNS policies and TCP/UDP forwarding. Real installed-app upgrade, macOS TUN authorization, physical-interface switching and sleep/wake under production traffic still require user testing. Existing host network settings were not changed during acceptance.

Includes the Apple Silicon mihomo v1.19.34 core. Update archives use Sparkle Ed25519 signatures. The app is ad-hoc signed and is not Apple-notarized.
