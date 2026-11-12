# Isolated Routing Lab

Run `scripts/preview-routing.sh --open` from the repository root. First preparation downloads pinned public assets; subsequent runs use the local cache. No production Swift sources, core binary, preferences, networking services or permission helpers are linked. The generated app is under `.build/routing-lab/` and does not replace `/Applications/Ares.app`.

- Native SwiftUI shell and inspector.
- MapLibre GL JS **5.12.0**, pinned classic browser bundle; latest 6.x uses an ESM/worker packaging arrangement and was not evaluated in this spike.
- SwiftUI Canvas alternative with Mercator projection and local world geometry.
- Natural Earth **5.1.2**, 1:110m countries, public-domain data. MapLibre license included in generated app resources. Assets are hash-checked. Runtime map has no remote tiles or geolocation service.
- Four deterministic synthetic scenarios; aggregation asserts conservation of both connection counts and bytes. Locations and arcs are fixtures, never real traffic evidence.

## Observed on 2026-11-12

| Check | Result |
| --- | --- |
| Build standalone arm64 app | Passed |
| Global scene | Both renderers draw shared geographic data and routes |
| Zoom out beyond default map constraints | MapLibre works with `transformConstrain`; minZoom alone was insufficient |
| Pacific route | Tokyo–San Francisco fits across the antimeridian in both renderers |
| Colocated | 2,000 records represented by one aggregate route, exact count/bytes retained |
| Stress | 20,000 records, 110 aggregate routes, 1,177 unlocated; both renderers displayed the scene |
| Selection | Native list selection highlights the MapLibre route; Fit Selection frames it |
| Appearance | Light/dark inspected; fixed background outside world bounds in dark mode |
| MapLibre first idle | Approximately 445–551 ms in observed local runs; cold page initialization, not an FPS benchmark |

## Recommendation and limits

Prefer MapLibre inside a native shell for the next prototype. Keep the Canvas renderer as a comparison, not a second production renderer. Full world overview and selected cross-Pacific framing are feasible. A world overview necessarily cuts some paths at its map seam; a selected route uses continuous longitude framing. Production needs a clear seam policy and stable camera ownership.

This spike is not a production performance acceptance test: 20k input records collapse to 110 geometries, and input aggregation happens during fixture generation. Continuous snapshot changes, 20k unique routes, sustained CPU/GPU/memory, high-latitude near-antipodal arcs, minimum window sizes and trackpad gesture behavior need dedicated testing. MapLibre idle duration includes rendering/fade/worker work and must not be compared directly to unmeasured Canvas frame time.

Canvas supports list selection, pan/pinch and fit controls, but lacks direct map hit testing and detailed labels. Its world-copy range is finite and its latitude projection clips near the poles. Neither renderer provides real node geolocation, physical router hops, or VLESS telemetry. These require the truthful route model described in `docs/design/routing-assessment.md`.
