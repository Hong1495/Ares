# Ares

A native macOS proxy client and network inspector, built with SwiftUI and powered by [mihomo](https://github.com/MetaCubeX/mihomo).

## Download

Get the latest DMG from [Releases](https://github.com/Hong1495/Ares/releases/latest), using the **arm64** package for Apple Silicon. Move Ares to Applications before opening it.

Requires an Apple Silicon Mac and macOS 14 or later. Starting with 1.0.2, Intel Macs are no longer supported. Current distributions use ad-hoc code signing and signed update archives; they are not Apple-notarized. macOS may require approval in System Settings → Privacy & Security for the first launch.

## Features

- Native sidebar, dashboard, traffic charts and menu-bar controls.
- HTTP, SOCKS5 and mixed proxy ports, plus TUN mode.
- Remote subscriptions, local profiles, node selection and latency checks.
- Routing rules, DNS settings, active connections and topology views.
- Resources: independent nodes, provider definitions and local subscription overrides.
- Devices: authenticated HTTP/SOCKS TCP access with per-entry routing and live connection visibility.
- Optional MITM inspection and certificate management.
- Automatic update checks, manual checks and an orange update indicator next to the window controls. Downloads and installation are user initiated.

Import a Clash-compatible profile in Proxy & Rules, select a node, then enable the connection mode you need. TUN and system proxy operations may request administrator authorization. MITM is optional and requires explicit certificate setup.

## Development

Use Xcode 26.2 or later (Swift 6.2 compiler). Build without running the production app:

```sh
git clone https://github.com/Hong1495/Ares.git
cd Ares
xcodebuild -project Ares.xcodeproj -scheme Ares -configuration Debug \
  -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

The app is at `.build/DerivedData/Build/Products/Debug/Ares.app`. Sparkle's pinned binary dependency is downloaded from its official release. Release packaging supplies the arm64 mihomo core.

For interface development, use the isolated executable:

```sh
scripts/preview-ui.sh --open
```

It shares presentation components with Ares and uses mock data. It does not start a core or change system networking. This enables UI work while your current proxy remains in use.

```sh
scripts/test-safe-functions.sh
python3 -m unittest discover -s scripts/tests -p 'test_*.py'
```

Read [development/testing](docs/development/testing.md) before testing live services. Production startup, shutdown, TUN, certificate and update-installation tests belong in a disposable VM. See [app updates](docs/diagnostics/app-updates.md) for signed release configuration and fork setup.

## Release status

The latest published version is available through Releases and the signed in-app updater. Resources and Devices are currently in development; see [workflow and validation details](docs/managed-resources-and-devices.md). Compilation and isolated tests are covered by CI. Full live-network and in-place update acceptance on Apple Silicon is still pending; see [functional verification](docs/diagnostics/functional-audit.md).

## License and credits

Ares source code is [MIT licensed](LICENSE). Bundled components retain their own licenses; see [Third-party notices](THIRD_PARTY_NOTICES.md). In particular, mihomo is a separate GPLv3 executable. Releases include the exact upstream source archive and GPL license for the bundled version. Sparkle is distributed under its upstream license.
