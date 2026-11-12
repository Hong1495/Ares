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

## Isolated spike result

A runnable comparison now lives in `DesignPreview/RoutingLab`; launch with `scripts/preview-routing.sh --open`. Both MapLibre 5.12.0/WKWebView and SwiftUI Canvas use the same offline Natural Earth geometry and fixtures. Observed global, Pacific, colocated and aggregated 20k-record scenes support MapLibre as the preferred next implementation. A `transformConstrain` override was needed to escape default zoom-out constraints. Selection fitting and light/dark behavior were exercised. See the lab README for specific results and remaining acceptance work; this does not establish production real-time performance or real-route correctness.

## Production implementation — build 901.9

Routing now uses the bundled MapLibre 5.12.0 renderer and Natural Earth 5.1.2 geometry. No remote tiles, geolocation API or DNS lookup is used; WKWebView is nonpersistent and its CSP blocks external requests. Native controls provide world view, fit all, focus selection, zoom, search of the full route list, and an optional inspector. Light/dark follows the app appearance. World view renders one world; fit mode permits wrapped worlds for Pacific routes. Date-line segments are split explicitly.

The foreground page polls the core's read-only connection snapshot every second, excludes Ares processes consistently with Activity, and keeps all sampled active connections. Identical route records aggregate counts and active-connection bytes. This is not lifetime traffic or a history of connections that ended between samples. Geometry is grouped by geographic endpoints without losing route membership; traffic-only updates do not cross the web bridge or reset the camera. Repeated clicks cycle routes sharing a geographic feature.

Metadata comes from the applied generated configuration, frozen for each connection when first observed by this page. The core chain is preserved verbatim. Concrete adapter entry addresses are configuration-derived; group names are not geographic hops. The remote egress and unreported intermediate hops remain unknown. Provider-only nodes and domain-only server addresses without known IP coordinates remain unlocated. There is no synthetic fallback. Dashed arcs show endpoint associations, not measured packet paths. A partially located route can appear on the map while retaining unknown segments in the inspector; the unlocated counter means **no** located endpoints.

The read-only MMDB decoder supports 24/28/32-bit trees, IPv4/IPv6, city/country records and mihomo Meta country-code arrays. Existing `geoip.metadb` is preferred after optional local city/country databases. Country-only records use explicitly labelled Natural Earth country representative points. Corrupt/missing files and private/FakeIP/documentation addresses remain unknown. User databases and subscription contents are not bundled or committed.

Validation: ARM64 Release build; 103 safe function tests; SubscriptionKit 11 tests (one pre-existing skip); geometry checks covering 20,000 route memberships, 300,000 bounds points, date-line splitting and degenerate endpoints. Read-only checks of the installed Meta database returned country codes for public IPv4/IPv6 examples. The production presentation/renderer was exercised in a separately compiled preview for light/dark, selection/focus, fit/zoom/world, inspector resizing, empty and unknown states. Unknown-state placement was corrected after screenshot review. This is not a claim of sustained 20k live-update frame-rate profiling or production core/TUN testing. No production core/proxy operations were performed.
