#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/.build/routing-page-preview/Ares Routing Preview.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
SOURCES=("$ROOT/Ares/Utilities/RouteSnapshot.swift" "$ROOT/Ares/UI/DesignSystem/DesignSystem.swift" "$ROOT/Ares/UI/DesignSystem/WorkspaceChrome.swift" "$ROOT/Ares/UI/DesignSystem/RoutingMapSurface.swift" "$ROOT/Ares/UI/DesignSystem/RoutingPresentation.swift" "$ROOT/DesignPreview/RoutingPagePreview.swift")
if rg -n 'AppState|ClashController|ClashViewModel|URLSession|Process\(|UserDefaults|AppStorage|CertificateManager|SystemProxyManager' "${SOURCES[@]}"; then exit 1; fi
xcrun swiftc -parse-as-library -target arm64-apple-macosx14.0 "${SOURCES[@]}" -o "$APP/Contents/MacOS/AresRoutingPreview"
ditto "$ROOT/Ares/Resources/Routing" "$APP/Contents/Resources"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>studio.hera.ares.routing-preview</string><key>CFBundleExecutable</key><string>AresRoutingPreview</string><key>CFBundleName</key><string>Ares Routing Preview</string><key>CFBundlePackageType</key><string>APPL</string><key>NSHighResolutionCapable</key><true/></dict></plist>
PLIST
if [[ "${1:-}" == "--open" ]]; then open "$APP"; fi
