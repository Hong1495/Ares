# Resources and Devices

These two workflows extend the existing subscription and policy features. They do not add historical traffic retention.

## Resources

Library → Resources shows the current subscription's static **Nodes** and **Node Providers**. Choose **Import Links** to paste one VLESS, Trojan or SIP002 Shadowsocks link per line, or use **Add Node** or **Add Provider**. Common node fields and HTTP provider URL/interval have forms; **Source** retains access to advanced settings. Unknown URI parameters are rejected instead of silently discarded. Unknown YAML fields survive edits.

Import and **Save to Draft** leave the running configuration alone. **Review & Apply** lists edits, additions, removals and restored definitions, then validates the complete merged configuration. A running core restarts; a stopped core stays stopped. Source subscription files are never rewritten. Changing a resource name does not rewrite references automatically. **Restore Inheritance** removes a local replacement; **Restore Removed Resource** removes an individual deletion marker.

After applying, select the saved resource and use **Add to Policy** to append it to an existing group. This leaves routing rules intact. Select a saved provider to see loaded members, update time, and measurements from the current profile's running core, or to request an update or health check. **Proxies** links to the same provider workspace. For use without a subscription, **Create Local Workspace** is available when the core is stopped; it creates a local profile with an Outbound selector.

## Devices

Routing → Devices creates named, authenticated HTTP/SOCKS TCP access entries. Each uses its own port, username, password and route. Use a specific address belonging to this Mac; loopback is the safe default, and wildcard binds are rejected. Configure the address and credentials on the connecting device. Enable, disable, change route or remove in the draft, then Apply. Applying replaces the core, so existing connections reconnect. REJECT blocks new traffic through the entry; disabling/removing removes its listener.

This is explicit proxy access, not discovery, DHCP, a router, transparent LAN capture, or a physical-device identity system. Anyone with an entry's credentials can use it. Only traffic sent through Ares is covered. UDP is disabled for these entries. The page attributes current connections by mihomo's exact inboundName and shows their current byte counters. It does not estimate historical totals or infer devices from an IP address. Pending settings do not claim to be active.

## Dashboard

Resources summarizes saved node/provider definitions and local/inherited sources. Devices summarizes configured/enabled entries and current active inbounds/connections. Runtime counts are unavailable while stopped or when a read fails; they are not shown as zero. Both headings open the corresponding management page. Summary sections share a three-column grid with aligned metric, content and footer rows; an incomplete last row leaves its trailing column empty.

## Storage and recovery

Each subscription has a private `managed/<UUID>.json` document containing resource overrides and device credentials. Its directory is mode 0700 and files are atomically replaced with mode 0600. Credentials are not included in catalog metadata or error messages. Corrupt storage fails closed and is not overwritten as empty. Removing a subscription also removes its private document. Scene changes retain this document; resource/device edits pause automatic scenes through the existing manual-change notification.

The service rejects stale subscription, policy, DNS, listener and local-rule baselines before applying and before stopping the old core. Validation/activation failures restore private preferences through the shared coordinator. A failed stopped-core edit also restores the previous generated configuration file, including when a baseline changes during validation. Existing full configuration validation and owned-listener checks cover the generated inbounds.

## Validation

- Package tests: YAML preservation, provider fields, link import/security/transport, duplicate names, removed references, credentials, route targets, wildcard binds and port conflicts.
- Production service with isolated storage and inert runtime: file permissions, stopped validation rollback, running activation rollback, stale editors/checkpoints, concurrent rule changes and corrupt-file preservation.
- Dedicated Linux VM, mihomo v1.19.34: production Swift-generated config; real authenticated HTTP/SOCKS TCP through the chosen upstream, inline provider visibility, exact inboundName attribution, REJECT behavior and disabled listener removal.
- Native macOS UI preview compiles production pages against mock services only. Production Debug compilation and existing regression suite run without launching the installed app.

Physical remote-device access through a macOS LAN interface and firewall remains a separate acceptance check. VM loopback tests do not establish that a particular host network allows inbound traffic. No host proxy, TUN, firewall or installed app is changed during development.
