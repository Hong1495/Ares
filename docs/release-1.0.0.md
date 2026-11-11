Ares 1.0.0 is the first release of the redesigned macOS client with signed app updates.

- Native SwiftUI workspace, simplified dashboard and consistent typography.
- Safer core ownership, verified proxy restoration and TUN/MITM recovery handling.
- Validated subscription updates, stale-response protection and corrected connection counts.
- Automatic/manual update checks and an orange update indicator beside the window controls.
- Separate Apple Silicon (`arm64`) and Intel (`x86_64`) packages.

**Install:** download the DMG for your Mac, then drag Ares into Applications. Earlier builds without update signing configuration need this one manual install; subsequent releases can use the built-in updater.

**Requirements:** macOS 14 or later. These packages are ad-hoc code signed and Ed25519 signed for updates, but are not Apple-notarized. First launch may need approval in System Settings → Privacy & Security.

**Validation:** production Release compilation, isolated UI preview, 53 standalone XCTest checks and 6 appcast tests. Real TUN, certificate and in-place update acceptance across both architectures remains pending; use appropriate network isolation when evaluating them.

The bundled mihomo core is GPLv3. Its exact upstream source archive, license and release metadata accompany these downloads. Ares source is MIT licensed; Sparkle retains its upstream license.
