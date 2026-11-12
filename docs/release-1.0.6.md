Ares 1.0.6 replaces the menu bar status dot with a compact boar mark based on the Ares app icon.

- The menu bar mark follows macOS light and dark appearance automatically.
- Latency is hidden by default; enable **Show latency next to Ares** in Settings → General → Menu Bar.
- The menu bar reads existing latency measurements and no longer starts its own recurring probe.
- Restores manual node selection in URLTest and Fallback groups, with an option to return to automatic selection. Choices persist across core and TUN restarts.
- Automatically measures node latency while the core runs. Node borders show green, yellow or red latency states; failed measurements no longer appear as fast connections.
- Recovers stale Ares-owned core processes before startup and waits for verified shutdown on quit, without terminating other proxy clients.

**Update:** use Ares → Check for Updates… or download the Apple Silicon DMG. Existing profiles and preferences are retained.

**Requirements:** Apple Silicon Mac, macOS 14 or later. The distributed Ares.app includes the matching mihomo v1.19.34 arm64 core in `Contents/Resources/clash-meta`; matching upstream source, release metadata and license accompany the release. The app and core are not published as separate installation steps. Packages use ad-hoc code signing and Ed25519 update signatures; they are not Apple-notarized. Intel is unsupported.

**Validation:** arm64 Release build, isolated regression suite and light/dark menu-bar previews. No production app, proxy core, System Proxy or TUN session was started during this release validation; live network behavior remains for installed-machine testing.

Ares is MIT licensed. The bundled mihomo core is GPLv3. Sparkle and Yams retain their upstream licenses, included with the app.
