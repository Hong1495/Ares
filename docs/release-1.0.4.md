Ares 1.0.4 restores the native macOS application menu.

- Run as a standard foreground application instead of an LSUIElement agent, restoring the Dock icon and native menu bar when Ares is active.
- Add Settings… (Command-comma) and Window → Show Main Window (Command-0).
- Keep the status bar entry and continue running when the last workspace window closes. Quit still uses the existing coordinated network cleanup.

**Validation:** arm64 Release compilation and built Info.plist inspection; standalone regression and subscription parser tests; native menu and Settings shortcut verified in the isolated preview using the same menu component. Production startup and network operations were not exercised.

**Update:** use the built-in update check or download the arm64 DMG. Requires Apple Silicon and macOS 14 or later. Packages use ad-hoc code signing and Ed25519 update signatures; they are not Apple-notarized.
