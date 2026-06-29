# Ares

A modern macOS proxy client powered by [mihomo](https://github.com/MetaCubeX/mihomo) (Clash Meta).

## Features

- SOCKS5 / HTTP / Mixed proxy modes
- TUN mode (virtual network interface)
- MITM domain filtering
- Custom routing rules with DNS fallback
- Multiple profiles with subscription support
- Dynamic menu bar icon with latency display
- Configurable keep-alive, UDP timeout, MTU

## Requirements

- macOS 14.0 or later
- Apple Silicon (arm64)

## Build

No Apple Developer account required.

```bash
git clone https://github.com/Hong1495/Ares.git
cd Ares

# Build (Debug, unsigned)
xcodebuild -project Ares.xcodeproj \
  -scheme Ares \
  -configuration Debug \
  build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO

# Run tests
xcodebuild -project Ares.xcodeproj \
  -scheme Ares \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  test \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO
```

The built app will be at `./build/Debug/Ares.app`. Move it to `/Applications` to use.

> **Note:** If you see a "damaged" warning on launch, run:
> `xattr -cr /Applications/Ares.app`

## Configuration

Place your Clash-compatible `config.yaml` in:

```
~/Library/Application Support/Ares/clash_user/config.yaml
```

## Credits

Powered by [mihomo](https://github.com/MetaCubeX/mihomo) (Clash Meta), licensed under GPLv3.

## License

MIT — see [LICENSE](LICENSE) for details.
