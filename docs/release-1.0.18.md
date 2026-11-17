# Ares 1.0.18

Applications now provides a focused table for managing saved application routes. Dashboard traffic history survives page navigation, and switching Proxies to Direct keeps the mode and search controls at the top. Requires macOS 14 or later on Apple Silicon. Includes mihomo v1.19.34.

- **Applications:** add discovered applications or choose an application from the Mac, select an existing entry, and edit its saved route. Follow rules, Direct, Block and configured policy or node targets share one editor. Executable checkboxes make the exact scope visible, including helpers with different routes. The table follows Activity's typography, spacing and native selection.
- **Verification:** separate saved configuration from actual connection evidence. Verification requires matching core-reported process paths, rules and route chains; existing connections cannot verify a newly changed rule. Mixed, pending, partial, conflicting and unavailable states remain explicit. Connection and rule details are available on demand, with guarded Undo and configuration refresh.
- **Dashboard:** retain the measured traffic window when leaving and returning to the page. Monitoring gaps remain gaps instead of invented zero samples or connected lines, and late messages from a replaced monitor cannot overwrite current rates.
- **Proxies:** keep the Rule / Global / Direct selector, search and actions in a stable toolbar. Direct, loading and empty states fill the remaining content area without moving the toolbar down the page.

Validated with isolated application-routing, traffic-history and configuration regression tests, native light/dark previews, production compilation and the release workflow's isolated bundled-core checks. Privileged process routing under TUN and in-place update installation remain local acceptance checks; development verification does not change the host's system proxy, DNS or TUN settings.

Update archives use Sparkle Ed25519 signatures. The app is ad-hoc signed and is not Apple-notarized. Intel Macs are not supported.
