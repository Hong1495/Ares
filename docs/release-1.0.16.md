# Ares 1.0.16

Resources and Devices now have dedicated management pages and live Dashboard summaries. Requires macOS 14 or later on Apple Silicon. Includes mihomo v1.19.34.

- **Resources:** add or edit nodes and provider definitions, import VLESS/Trojan/SIP002 Shadowsocks links, and maintain local overrides without rewriting subscription files. Imported resources are available to policy composition and routing. Advanced YAML fields are preserved; unsupported link parameters are rejected.
- **Devices:** configure named HTTP/SOCKS TCP proxy access entries with individual credentials, local addresses, ports and routes. Enable or disable access and inspect current connections attributed to the exact inbound. Devices must be configured to use this proxy; this is not automatic LAN discovery or transparent routing. UDP is not enabled for these entries.
- **Dashboard:** resource and device counts join Applications, Policies and Scenes in a shared three-column grid. The second row leaves the right column empty. Headings, metrics, detail rows and footers align; unavailable connection data displays a dash.
- **Configuration safety:** private per-subscription resource and credential storage, full configuration validation, stale-edit protection and recovery on failed activation. Failed edits while stopped also restore the previous generated configuration. Applying changes restarts a running core; a stopped core remains stopped.
- **Interface:** English labels, shared collection controls and aligned device editor fields.

Validation includes the isolated regression suite, native previews, production compilation and real mihomo HTTP/SOCKS authentication, routing, inbound attribution, blocking and listener removal in an isolated test environment. Physical remote-device access through a Mac's LAN interface and firewall still requires local acceptance testing.

Update archives use Sparkle Ed25519 signatures. The app is ad-hoc signed and is not Apple-notarized. Intel Macs are not supported.
