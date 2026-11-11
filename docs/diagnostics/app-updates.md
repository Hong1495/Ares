# Ares app updates

Ares uses Sparkle 2.9.6 for signed application updates. This is separate from mihomo core updates. The update indicator is a small orange dot after the native green button, with the same center spacing as green/yellow. The native buttons are never repositioned.

## Behaviour

- Automatic checks default to enabled, with a requested 30-minute interval (Sparkle may enforce its own minimum). They show only the update dot, without stealing focus.
- Settings → General → Software Update and the Ares menu provide manual checks. The dot opens Sparkle's update dialog, release details, download progress and installation controls.
- Downloads/installations require user interaction. Switching off automatic checks does not disable manual checks.
- A signed application archive is verified by Sparkle before installation.
- Before installation/relaunch, `AppUpdateService` waits for `AppTerminationCoordinator.prepareForTermination()`. A failure retains the pending installer callback for a user retry; it must never force quit or stop other proxy processes.
- macOS full-screen mode hides the dot; the app menu remains available.
- Builds without a valid `SUPublicEDKey` do not start the updater. Settings shows an explicit configuration message. No placeholder or Bee signing key is used.

## First release setup

The upstream repository is configured for 1.0.0. Forks require their own one-time repository configuration. Use a dedicated Ares signing identity; keep the same identity across subsequent releases.

1. Download Sparkle 2.9.6 tools from its official GitHub release and verify the archive's SHA-256 (`52bf9e88cdd972fc0c81501377a880e90d47031bd8ca5462488f843e2609e192`).
2. Run `bin/generate_keys --account studio.hera.ares`. This creates a key in the maintainer's login Keychain. It is a release-maintenance action, not part of app startup or development tests.
3. Put the displayed public key in the GitHub repository **variable** `ARES_UPDATE_PUBLIC_KEY`.
4. Export using `bin/generate_keys --account studio.hera.ares -x /secure/location/ares-update-key`. Store the file's contents in the repository **secret** `ARES_UPDATE_PRIVATE_KEY`, keep an offline backup, and remove the temporary export securely. Never commit the export.
5. Configure the same public key for any locally distributed build: `xcodebuild ... ARES_UPDATE_PUBLIC_KEY="$ARES_UPDATE_PUBLIC_KEY"`.
6. Push a stable `vMAJOR.MINOR.PATCH` tag when ready to publish. The release workflow runs on stable version tags.

The workflow builds arm64 and x86_64 independently, sets app versions from the tag and an increasing CI build number, embeds the matching mihomo binary, creates ZIP and DMG artifacts, signs the ZIP and XML feed, and only publishes once both architectures are ready. Both appcasts are assets of the same latest release:

- `https://github.com/Hong1495/Ares/releases/latest/download/appcast-arm64.xml`
- `https://github.com/Hong1495/Ares/releases/latest/download/appcast-x86_64.xml`

The app chooses the feed for its compiled architecture, including Intel apps running through Rosetta. The base repository URL can be overridden using `ARES_UPDATE_FEED_URL`; forks must provide their own URL and signing keys. XML construction escapes release content and requires a stable tag, a nonempty archive and a correctly sized Ed25519 signature. Actual archive verification is Sparkle's responsibility.

`Packages/Sparkle/Package.swift` is the official binary package manifest pinned to 2.9.6 and its SHA-256. Keeping this small manifest locally avoids downloading Sparkle's complete Git history. The framework itself downloads from the official release and is not vendored. Its license accompanies the manifest.

## Distribution limitations

The existing project has no Developer ID signing/notarization identity. CI applies ad-hoc signing for bundle consistency and EdDSA for update authenticity; this does **not** grant Apple notarization. First-install Gatekeeper behaviour must be verified before public distribution, or Developer ID signing/notarization added. An existing unsigned build without the public key needs one manual install of the first update-enabled release.

The repository can remain private during development, but the updater feed and release assets must be publicly readable before shipping; no GitHub access token is embedded in the app. Opening source code alone does not publish an update: a signed release is required.

## Validation

Only the isolated presentation preview is launched on the development host. It uses a fake `1.1` availability flag and a mock alert, with no Sparkle import, network transport, production app delegate or core. Real download, signature rejection, replacement and restart tests belong in a disposable VM, including failed network restoration and both architectures.

Implementation verification on 2026-11-11: production Debug build passed without launching it; Sparkle.framework is embedded and SU* keys are present with correct Boolean/integer types in the built Info.plist. 53 isolated XCTest cases and 6 Python appcast cases passed. The preview dot was visible and its click opened the mock update alert. Production update services and archive replacement were not executed. Release setup is documented separately from those implementation-only checks.
