# Routing assessment — 2026-11-12

Scope: move Routing beside Activity in Monitoring; evaluate replacement, do not implement a new map yet.

## Existing implementation

`RouteMapPageView.swift` uses MKMapView with a fixed 40,000 km camera distance. The SwiftUI camera binding is never applied by the representable. There is no fit-to-routes operation. Local coordinates are fixed to Shanghai; destination coordinates are hash-selected from predefined hubs. Geodesic arcs are illustrations, not measured paths. The current map ignores proxy-chain geography. Every update removes/recreates all annotations and overlays; IDs are random. Deduplication retains the first connection's download instead of aggregating traffic, and drops the rest for that source/destination key.

## Recommendation

First validate MapLibre GL JS embedded locally in WKWebView, keeping navigation, toolbar, inspector, and controls native. Use a subdued 2D map, full-world view, Fit All / Fit Selection, controlled zoom limits, antimeridian-aware extents and route splitting. Bundle the renderer, pin dependency versions, and choose licensed local or hosted base data separately; renderer availability does not imply free map tiles. Avoid presenting third-party tile requests as privacy-free.

A native SwiftUI Canvas/Metal renderer with bundled low-resolution world geometry is a strong alternative if offline global monitoring matters more than street-level cartography. It provides exact layout/projection control but requires custom hit testing, labels, zoom, accessibility, and rendering work.

Retaining MapKit can repair camera binding, fitting and incremental updates, but does not establish that its world framing will satisfy the required UX. MapLibre Native macOS is not the first choice: upstream describes macOS as mainly used for development with legacy AppKit code; iOS and Android are its core platforms. deck.gl can be evaluated later for large GPU line layers; do not introduce it without profiling. A globe is optional, not the default: its far side hides connections.

## Truth model

Store logical route and geographic estimates separately. Distinguish runtime-observed, configuration-derived, actively probed, inferred and unknown facts. Preserve connection snapshot time and route selection at creation, rather than reinterpreting old connections using a group's current selection. Node entry address, server egress IP, and target are distinct. VLESS does not expose physical hops; dialer-proxy describes logical chaining, not router paths. Core chains must be normalized and tested against concrete chain configurations, never interpreted as one geographic hop per string.

An IP database estimates geography; country-only data must not be presented as city precision. Fake-IP, private/unresolved addresses and unlocated nodes remain visible in an unknown/unlocated list. Remote-side path probes require controlled remote agents or another explicitly supported measurement method. Local traceroute cannot reveal a complete path inside and beyond an encrypted tunnel. No fabricated hops or submarine-cable paths.

## Delivery sequence / acceptance

1. Accurate route snapshot model and source labels; eliminate simulated geography. Preserve all connections and aggregate counts/bytes exactly.
2. Isolated map spike: full-world and selected-route fitting, Pacific crossings, colocated endpoints, light/dark, minimum window, trackpad controls. Compare MapLibre against native canvas before choosing.
3. Incremental scene updates, stable IDs, clustering and drill-down; aggregate all records while reducing rendered objects. Display unknown-location totals. Never silently truncate to a connection limit.
4. Multi-hop logical routes and optional explicit diagnostics. Probe results include timestamp, method, scope and unavailable segments.

Sources:
- https://maplibre.org/maplibre-gl-js/docs/API/type-aliases/MapOptions/
- https://maplibre.org/maplibre-gl-js/docs/API/type-aliases/FitBoundsOptions/
- https://maplibre.org/maplibre-native/docs/book/platforms/index.html
- https://deck.gl/docs/api-reference/layers/arc-layer
- https://wiki.metacubex.one/config/proxies/dialer-proxy/
- https://wiki.metacubex.one/api/
