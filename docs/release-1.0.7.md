# Ares 1.0.7

This release refines the macOS interface across Dashboard, Proxies, Subscriptions, Rules and Logs. Requires macOS 14 or later on Apple Silicon; Intel Macs are not supported.

- Dashboard uses compact native switches, separate upload/download charts with continuously scrolling time axes, and automatic website response-time checks every 30 seconds while the page is open.
- Optional exit IP risk checks are available in Settings. Results appear after Exit IP in the title bar, use proxycheck.io's 0–100 risk score, and are cached per IP for six hours. The feature is off by default; enabling it shares the displayed exit IP with the provider. This is a provider risk assessment, not a purity percentage.
- Proxy cards show subscription country hints and latency along their upper edge, with neutral borders and a clear selected state. Nodes sort by country, then latency. Node counts move to the title bar, and search and action controls follow the shared page layout.
- Subscriptions and Rules use consistent title metrics and tools. Subscription cards show the source host, usage and selection; search supports subscription names and hosts.
- Logs uses compact level filters and icon actions, exports the currently matching lines, reports export failures, and continues following new entries after the log buffer reaches its limit.

Includes the Apple Silicon mihomo v1.19.34 core. Existing installations with automatic updates configured can install this release through Check for Updates. Update archives use Sparkle Ed25519 signatures; the app is ad-hoc signed and is not Apple-notarized.
