#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/.build/design-preview"
APP="$OUT/Ares Design Preview.app"
mkdir -p "$APP/Contents/MacOS"
# Explicit allowlist: never compile AresApp, AppDelegate, services, models,
# production page wrappers, resources, or core binaries into this executable.
SOURCES=(
  "$ROOT/Ares/UI/DesignSystem/DashboardTitleSummary.swift"
  "$ROOT/Ares/UI/DesignSystem/SettingsPresentation.swift"
  "$ROOT/DesignPreview/SettingsPreview.swift"
  "$ROOT/Ares/UI/DesignSystem/DesignSystem.swift"
  "$ROOT/Ares/UI/DesignSystem/WorkspaceChrome.swift"
  "$ROOT/Ares/UI/DesignSystem/ActivityViewPicker.swift"
  "$ROOT/Ares/UI/DesignSystem/ActivityTitleToolbar.swift"
  "$ROOT/Ares/UI/DesignSystem/AresMenuBarLabel.swift"
  "$ROOT/Ares/UI/DesignSystem/WindowUpdateIndicator.swift"
  "$ROOT/Ares/UI/DesignSystem/OverviewPresentation.swift"
  "$ROOT/Ares/UI/DesignSystem/ProxyNodeTile.swift"
  "$ROOT/DesignPreview/AresDesignPreview.swift"
)
if rg -n 'AppState|ClashController|ClashViewModel|AppDelegate|URLSession|NWListener|Process\(|UserDefaults|AppStorage|CertificateManager|SystemProxyManager|NetworkMITMService' "${SOURCES[@]}"; then
  echo "Preview isolation check failed: production dependency found." >&2
  exit 1
fi
xcrun swiftc -parse-as-library -module-name AresDesignPreview -target "$(uname -m)-apple-macosx14.0" "${SOURCES[@]}" -o "$APP/Contents/MacOS/AresDesignPreview"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>studio.hera.ares.design-preview</string>
<key>CFBundleExecutable</key><string>AresDesignPreview</string>
<key>CFBundleName</key><string>Ares Design Preview</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
printf 'Built isolated preview: %s\n' "$APP"
if [[ "${1:-}" == "--open" ]]; then
  open "$APP"
fi
