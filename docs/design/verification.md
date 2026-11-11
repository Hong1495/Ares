# Interface verification — 2026-11-11

- Production Debug compilation: passed (no application launch).
- Isolated preview compilation and explicit dependency allowlist scan: passed.
- Native preview startup, shutdown, and restart: exercised.
- Shared dashboard, chart, connection controls, native sidebar/toolbars: visually inspected in light and dark modes.
- Mode selection: switched Rule → Global; selected state updated (prior pass).
- Mock system proxy toggle: state switched to Stopped, traffic and connection count became zero.
- Dashboard configuration: all six baseline information areas are always expanded in the shared responsive grid. Removed repeated runtime/API/mode summaries; DNS and bypass lists wrap without disclosure controls.
- Chart history selection: numeric readouts and timestamp changed with selection.
- Wide layout: corrected the three-detail grid so no empty fourth column remains.
- Source diff whitespace check: passed.
- Existing SettingsViewSourceTests: 10 passed, 0 failures. Compiled as a standalone XCTest bundle containing only source-reading tests; no production app or service code linked.

Not verified: compact window layout, live data/service behavior,
and full visual parity of secondary pages. UI automation repeatedly yielded to
user interaction in the preview window, so these states are not claimed as passed.
Secondary preview pages contain fixtures and do not exercise production services.

Only the isolated executable was launched. Production hosted tests were not run.
No system proxy, DNS, routes, TUN interfaces, certificates, helpers, or existing
proxy processes were changed for verification.

## Typography and toolbar pass

- Removed both right-side toolbar controls in the preview, and the redundant quick-proxy toolbar button in production. System proxy remains in Dashboard and the existing menu-bar app controls.
- Fixture toggles moved to the preview executable's macOS Preview menu; verified dark toggle still works.
- Audited explicit font declarations throughout Ares/UI, including all eight main destinations, subscription/rules screens, menu-bar UI, and inspectors. Replaced arbitrary small sizes with shared native styles in DS.Typography. Retained separate large symbol sizes and key metric emphasis.
- Dashboard: removed traffic/control section headings, redundant node/group counts, and separate subscription/profile heading lines. Moved version/ports to a footer. System fields use two compact lines. All configuration remains expanded.
- Visually checked updated Dashboard (light/dark), proxy tiles, settings fixtures, and activity fixtures in the isolated preview. No clipping observed at the inspected wide window size.
- Production compilation and preview allowlist build passed. Full production data layouts, compact windows, and accessibility settings have not been visually verified; secondary preview pages remain illustrative.

Reference: [Apple HIG — Typography](https://developer.apple.com/design/human-interface-guidelines/typography). Apple's platform guidance lists macOS default text as 13 pt and minimum text as 10 pt, recommends built-in text styles, and cautions against light weights for small text.

## Sidebar edge placement

- Native sidebar toggle now lives in the sidebar toolbar at its trailing edge, rather than beside the detail title.
- Borderless AppKit button preserves the native toolbar item's placement and responder-chain toggle action. On macOS 27 the SwiftUI-generated sidebar item identifier is matched as a compatibility fallback; recheck this adapter on future OS updates.
- Isolated preview: verified a single borderless icon, successful collapse, and successful reopening. No production app launched.
