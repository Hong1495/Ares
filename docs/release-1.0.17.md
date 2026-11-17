# Ares 1.0.17

Proxies now uses a native macOS table with a dedicated group list, replacing repeated node cards. Requires macOS 14 or later on Apple Silicon. Includes mihomo v1.19.34.

- **Proxies:** choose a group on the left and compare Name, Country, Type and Latency in aligned columns. Nodes remain sorted by country, then latency, with the existing latency colors and millisecond units. Country codes are derived from subscription names.
- **Selection and testing:** use the selection control or double-click a row to choose a node, including nested groups. Automatic groups support pinning and Resume Auto. Single-node and batch latency testing, search and saved offline choices remain available. Load-balancing groups retain automatic per-connection selection.
- **Dashboard:** Activity uses a horizontal connection-count chart with separate name, plot and value columns to prevent overlapping labels. Network Quality is shortened to Quality throughout the interface.
- **Layout:** shared typography, hidden scrollbars, compact utility icons and columns that fit narrow windows in light and dark appearances.

Validation includes isolated node-selection and controller regression tests, native preview checks for group selection, automatic selection, search, latency updates and offline choices, and production compilation. Live proxy/TUN behavior and in-place update installation were not exercised on the development host.

Update archives use Sparkle Ed25519 signatures. The app is ad-hoc signed and is not Apple-notarized. Intel Macs are not supported.
