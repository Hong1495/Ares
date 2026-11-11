Ares 1.0.2 supports Apple Silicon Macs only.

- Release and development builds now target arm64. Intel (x86_64) packages and update feeds are no longer produced.
- Packaging rejects non-arm64 application executables; core downloads use the arm64 mihomo binary.
- Includes the subscription configuration and node-loading fixes from 1.0.1.

**Update:** Apple Silicon users can update through Ares's built-in update check or download the arm64 DMG. Saved subscriptions and settings are retained. Historical Intel releases remain archived, but will receive no further updates.

**Requirements:** Apple Silicon Mac, macOS 14 or later. Packages use ad-hoc code signing and Ed25519 update signatures; they are not Apple-notarized.

**Validation:** arm64 compilation, standalone regression tests, appcast tests, archive architecture and update-signature checks. Production startup, network operations and update installation are not run on the development host.

The bundled mihomo core is GPLv3. Its exact upstream source archive, license and release metadata accompany these downloads. Ares source is MIT licensed; Sparkle retains its upstream license.
