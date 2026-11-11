#!/bin/bash
set -euo pipefail
# Package an already built release app. Never start Ares or its core during packaging.
APP="${1:?Usage: package.sh /path/to/Ares.app version arch output-directory}"
VERSION="${2:?Missing version}"
ARCH="${3:?Missing architecture}"
OUTPUT="${4:?Missing output directory}"
[[ "$ARCH" == arm64 ]] || { echo "Ares supports Apple Silicon (arm64) only." >&2; exit 1; }
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 1
[[ -d "$APP/Contents" ]] || exit 1
[[ "$(lipo -archs "$APP/Contents/MacOS/Ares")" == arm64 ]] || { echo "Expected an arm64-only Ares executable." >&2; exit 1; }
mkdir -p "$OUTPUT"
STAGING=$(mktemp -d /tmp/ares-package.XXXXXX)
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP" "$STAGING/Ares.app"
ln -s /Applications "$STAGING/Applications"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUTPUT/Ares-v$VERSION-$ARCH.zip"
hdiutil create -volname Ares -srcfolder "$STAGING" -ov -format UDZO "$OUTPUT/Ares-v$VERSION-$ARCH.dmg"
