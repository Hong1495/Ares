#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/.build/routing-lab"
APP="$OUT/Ares Routing Lab.app"
python3 "$ROOT/DesignPreview/RoutingLab/prepare.py"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
xcrun swiftc -parse-as-library -target arm64-apple-macosx14.0 "$ROOT/DesignPreview/RoutingLab/RoutingLab.swift" -o "$APP/Contents/MacOS/AresRoutingLab"
ditto "$OUT/assets" "$APP/Contents/Resources/assets"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>studio.hera.ares.routing-lab</string><key>CFBundleExecutable</key><string>AresRoutingLab</string><key>CFBundleName</key><string>Ares Routing Lab</string><key>CFBundlePackageType</key><string>APPL</string><key>NSHighResolutionCapable</key><true/></dict></plist>
PLIST
printf 'Built isolated routing lab: %s\n' "$APP"
if [[ "${1:-}" == "--open" ]]; then open "$APP"; fi
