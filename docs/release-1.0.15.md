# Ares 1.0.15

This update fixes Dashboard summary alignment. Requires macOS 14 or later on Apple Silicon. Includes mihomo v1.19.34.

- Applications, Policies and Scenes now share one three-column grid. Headings, metrics, content starts and status text align consistently, even when the sections contain different numbers of entries.
- Removed the independent-column flow that placed Applications below Policies and Scenes, along with unnecessary fixed blank space in the summaries.

The shared production view was compiled in the isolated native preview and visually checked in dark appearance. Release validation includes production compilation, isolated regression tests and bundled-core checks. Proxy behavior, monitoring settings and saved configurations are unchanged.

Update archives use Sparkle Ed25519 signatures. The app is ad-hoc signed and is not Apple-notarized. Intel Macs are not supported.
