#!/usr/bin/env bash
set -euo pipefail

# Usage: ./scripts/package.sh <arch>
#   arch: arm64 | x86_64
#
# Builds Ares.app for the given architecture, downloads the matching
# mihomo binary, and packages everything into a DMG.

ARCH="${1:?Usage: $0 <arm64|x86_64>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$ROOT/.build/$ARCH"
APP_DIR="$BUILD_DIR/Ares.app"
RESOURCES_DIR="$APP_DIR/Contents/Resources"
STAGING="/tmp/Ares-$ARCH"

case "$ARCH" in
  arm64)  MIHOMO_ARCH="arm64"  ;;
  x86_64) MIHOMO_ARCH="amd64"  ;;
  *)
    echo "Unsupported architecture: $ARCH" >&2
    echo "Usage: $0 <arm64|x86_64>" >&2
    exit 1
    ;;
esac

echo "=== 1/5 Download mihomo for $ARCH ==="
RELEASE_JSON=$(curl -fsS \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/MetaCubeX/mihomo/releases/latest")

ASSET_NAME=$(echo "$RELEASE_JSON" | python3 -c "
import json, sys
r = json.load(sys.stdin)
names = [a['name'] for a in r.get('assets', [])]
# prefer: darwin-<arch> without go suffix
matches = [n for n in names if 'darwin-$MIHOMO_ARCH' in n.lower()]
preferred = [n for n in matches if '-go' not in n.lower() and 'compatible' not in n.lower()]
best = (preferred or matches)[0]
print(best)
")

ASSET_URL=$(echo "$RELEASE_JSON" | python3 -c "
import json, sys
r = json.load(sys.stdin)
url = [a['browser_download_url'] for a in r.get('assets', []) if a['name'] == '$ASSET_NAME'][0]
print(url)
")

TAG=$(echo "$RELEASE_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['tag_name'])")

MIHOMO_PATH="$RESOURCES_DIR/clash-meta"
mkdir -p "$RESOURCES_DIR"

echo "  → $ASSET_NAME ($TAG)"
curl -fsSL "$ASSET_URL" | gunzip > "$MIHOMO_PATH"
chmod +x "$MIHOMO_PATH"

"$MIHOMO_PATH" -v

echo
echo "=== 2/5 Build Ares.app ($ARCH) ==="
xcodebuild -project "$ROOT/Ares.xcodeproj" \
  -scheme Ares \
  -configuration Release \
  -derivedDataPath "$ROOT/.build/DerivedData/$ARCH" \
  ARCHS="$ARCH" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build

# Copy built app from DerivedData
PRODUCT_DIR="$ROOT/.build/DerivedData/$ARCH/Build/Products/Release"
cp -R "$PRODUCT_DIR/Ares.app" "$APP_DIR"

# Embed mihomo into the copied app
cp "$MIHOMO_PATH" "$APP_DIR/Contents/Resources/clash-meta"
chmod +x "$APP_DIR/Contents/Resources/clash-meta"

echo
echo "=== 3/5 Verify packaged binary ==="
"$APP_DIR/Contents/Resources/clash-meta" -v

echo
echo "=== 4/5 Create DMG ==="
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP_DIR" "$STAGING/"

DMG_NAME="Ares-${TAG}-${ARCH}.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"

# Create symlink to /Applications for drag-to-install
ln -s /Applications "$STAGING/Applications"

hdiutil create -volname "Ares" \
  -srcfolder "$STAGING" \
  -ov -format UDZO \
  "$DMG_PATH"

rm -rf "$STAGING"

echo
echo "=== 5/5 DMG ready ==="
echo "  $DMG_PATH"
ls -lh "$DMG_PATH"
echo
echo "SHA-256:"
shasum -a 256 "$DMG_PATH"
