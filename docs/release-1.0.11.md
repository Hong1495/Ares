# Ares 1.0.11

This release adds editable scenes, verified node and mode switching, optional network-triggered scenes, and scene execution history. Requires macOS 14 or later on Apple Silicon; Intel Macs are not supported.

- Edit saved scenes independently: rules, DNS, policy parameters, routing/listeners, proxy mode, node selections and environment conditions. Saving a draft leaves the current network unchanged.
- Choose scene nodes from subscription groups or the matching running core, including provider members. Missing choices are visible; explicit selections must be confirmed by the core. Failed activation restores the previous runtime and settings. Session-local undo includes mode and saved node choices.
- Preview network-condition matches and priorities. Automatic switching is off by default and requires explicit enablement. Matches must remain stable for 10 seconds; attempts have a 30-second cooldown. Conflicts, stopped/busy cores, changed subscriptions and failed switches are handled explicitly. Sleep and manual scene/node/mode changes pause automation; pause persists across launches. System proxy and TUN switches remain separate.
- After a subscription update, Review and Apply validates the scene against the new content. Only a successful running-core switch approves the new revision for automatic use. Offline saves and failed switches do not approve migration.
- Inspect the last 100 scene attempts with trigger, outcome and changed sections. History excludes configuration values, node credentials and network identifiers; damaged history is retained rather than silently overwritten.
- Spread out the Proxies toolbar with quieter icons and separate action groups. Hide horizontal and vertical scrollbars throughout the app while retaining scrolling, including topology, tables and editors.
- Reject overrides for removed policy groups instead of silently ignoring them. Preserve explicit empty strings in scene YAML editing. Strengthen environment checks before stopping the previous core and before committing a switch.

Network conditions currently describe system-reported connection type, interface, metered status and Low Data Mode. They do not identify a trusted home/office network or inspect SSIDs. A stopped-core scene's dynamic provider selections are checked when the core next starts. Advanced configuration sections retain YAML editing.

Validated using isolated production-service harnesses, configuration tests, real native loopback mihomo traffic and arm64 builds. Physical network switching, real macOS TUN authorization, sleep/wake with production traffic and signed installed-app update/relaunch remain user acceptance items. The development checks did not change the host's system proxy or TUN.

Includes mihomo v1.19.34 for Apple Silicon. Update archives use Sparkle Ed25519 signatures. The app is ad-hoc signed and is not Apple-notarized.
