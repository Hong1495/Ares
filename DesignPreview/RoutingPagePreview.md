# Production Routing presentation preview

Run `bash scripts/preview-routing-page.sh --open` from the repository. The separate `Ares Routing Preview` app compiles production presentation, geometry and renderer files with deterministic sample data. It does not link production services, use defaults, launch a core or alter proxy/TUN state. Sample controls toggle light/dark, empty and unlocated snapshots.

Run `node scripts/test-routing-geometry.cjs` for geometry/large input checks and `bash scripts/test-safe-functions.sh` for the isolated Swift suite. Bundled map data and notices live in `Ares/Resources/Routing`.
