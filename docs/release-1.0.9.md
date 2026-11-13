# Ares 1.0.9

This release improves the menu bar panel, app icon appearances, and update discovery. Requires macOS 14 or later on Apple Silicon; Intel Macs are not supported.

- Keeps the original color app icon and adds a graphite dark icon with a simplified boar. On supported macOS versions, the system icon appearance setting selects the appropriate variant.
- Simplifies the menu bar boar and improves the contrast and spacing of Activity, Settings, and Quit actions. Exit information and traffic rates share aligned columns.
- Checks for updates at launch when automatic checks are enabled, while keeping the existing scheduled checks. Available updates also appear inside the menu bar panel.
- Avoids repeating network cleanup after a successful update handoff. Adds startup version, process, update scheduling, and relaunch diagnostics to help investigate update issues.
- Includes formatted release notes in the update window. The isolated menu preview no longer adds a second menu bar icon.

Includes the Apple Silicon mihomo v1.19.34 core. Update archives use Sparkle Ed25519 signatures; the app is ad-hoc signed and is not Apple-notarized. The revised relaunch flow still needs confirmation during a real installed-app update; no production network session was interrupted for testing.
