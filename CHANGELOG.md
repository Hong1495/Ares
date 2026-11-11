# Changelog

## 1.0.0

- Rebuilt the macOS workspace, dashboard, typography and sidebar controls.
- Added an isolated UI preview for design without starting proxy services.
- Replaced port-based process termination with owned-process lifecycle handling.
- Added verified proxy restoration and explicit TUN/MITM recovery failures.
- Validated subscription responses before replacement and rejected stale concurrent updates.
- Fixed node API error reporting, path encoding and dashboard connection counts.
- Added manual/automatic app update checks, a native-window update indicator and signed Sparkle releases for Apple Silicon and Intel.

The older `v0.1` release remains available as project history. Existing builds without update signing configuration require a manual installation of 1.0.0.
