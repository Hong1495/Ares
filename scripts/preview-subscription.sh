#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PACKAGE="$ROOT/Packages/SubscriptionKit"
OUT="$ROOT/.build/subscription-preview"
APP="$OUT/Ares Subscription Preview.app"
swift build --build-system native --package-path "$PACKAGE"
BIN="$(swift build --build-system native --package-path "$PACKAGE" --show-bin-path)"
mkdir -p "$APP/Contents/MacOS"
# Explicit allowlist. All service names resolve to inert mocks in SubscriptionPreview.
OBJECTS=()
while IFS= read -r file; do OBJECTS+=("$file"); done < <(find "$BIN/Yams.build" "$BIN/CYaml.build" "$BIN/SubscriptionKit.build" -name '*.o')
xcrun swiftc -parse-as-library -target arm64-apple-macosx14.0 \
  -I "$BIN/Modules" -I "$PACKAGE/.build/checkouts/Yams/Sources/CYaml/include" \
  "$ROOT/Ares/Models/ProxyModels.swift" \
  "$ROOT/Ares/Models/ClashConfig.swift" \
  "$ROOT/Ares/Utilities/ClashPorts.swift" \
  "$ROOT/Ares/Utilities/DefaultsKeys.swift" \
  "$ROOT/Ares/UI/DesignSystem/DesignSystem.swift" \
  "$ROOT/Ares/UI/DesignSystem/ProxyNodeTile.swift" \
  "$ROOT/Ares/UI/DesignSystem/WorkspaceCommands.swift" \
  "$ROOT/Ares/UI/ProxiesView.swift" \
  "$ROOT/DesignPreview/SubscriptionPreview.swift" \
  "${OBJECTS[@]}" -o "$APP/Contents/MacOS/SubscriptionPreview"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>studio.hera.ares.subscription-preview</string>
<key>CFBundleExecutable</key><string>SubscriptionPreview</string>
<key>CFBundleName</key><string>Ares Subscription Preview</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
if [[ "${1:-}" == "--open" ]]; then open "$APP"; fi
