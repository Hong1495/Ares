# Isolated Ares UI preview

Build and open from the repository root:

```sh
./scripts/preview-ui.sh --open
```

The script compiles an explicit allowlist of presentation files plus
`AresDesignPreview.swift`. It does not link the production app, delegate, services,
core executable, certificates, or production resources. Startup and termination
are ordinary SwiftUI window lifecycle only. All demo controls change `@State`;
there is no application preference storage or network traffic. The preview app
has its own bundle identity and normal window restoration storage managed by macOS.
The allowlist, rather than the bundle identifier, is the isolation boundary.

The dashboard layout, chart, connection controls, sidebar, tabs, and proxy tiles
are shared with production. Other preview pages are illustrative fixtures, not
full replicas of live services. Topology and Routing intentionally show empty
states instead of loading maps or network data.

Use the macOS menu bar's Preview menu for empty/error/dark states. The window toolbar contains only navigation; fixture controls do not appear in the product chrome. Do not launch
Ares.app for interface inspection. Real core/service tests belong in a disposable
VM, as described in [development testing](../docs/development/testing.md).
