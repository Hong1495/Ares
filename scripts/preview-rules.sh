#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/.build/rules-preview/Ares Rules Preview.app"
mkdir -p "$APP/Contents/MacOS"
PACKAGE="$ROOT/Packages/SubscriptionKit"
swift build --build-system native --package-path "$PACKAGE"
BIN="$(swift build --build-system native --package-path "$PACKAGE" --show-bin-path)"
OBJECTS=()
while IFS= read -r file; do OBJECTS+=("$file"); done < <(find "$BIN/Yams.build" "$BIN/CYaml.build" "$BIN/SubscriptionKit.build" -name '*.o')
# Actual views, but all services and preference storage are inert local mocks.
xcrun swiftc -parse-as-library -target arm64-apple-macosx14.0 \
  -I "$BIN/Modules" -I "$PACKAGE/.build/checkouts/Yams/Sources/CYaml/include" \
  "$ROOT/Ares/Services/ResourceActivity.swift" "$ROOT/Ares/UI/ResourceActivityView.swift" \
  "$ROOT/Ares/Models/RuleModels.swift" "$ROOT/Ares/Utilities/DefaultsKeys.swift" \
  "$ROOT/Ares/UI/DesignSystem/DesignSystem.swift" \
  "$ROOT/Ares/UI/DesignSystem/WorkspaceChrome.swift" \
  "$ROOT/Ares/UI/DesignSystem/CollectionPresentation.swift" \
  "$ROOT/Ares/UI/RulesView.swift" "$ROOT/Ares/UI/RuleProvidersView.swift" \
  "$ROOT/Ares/UI/LocalRulesEditorView.swift" "$ROOT/Ares/UI/RuleSourcesView.swift" \
  "$ROOT/DesignPreview/RulesPreview.swift" "${OBJECTS[@]}" -o "$APP/Contents/MacOS/RulesPreview"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>studio.hera.ares.rules-preview</string>
<key>CFBundleExecutable</key><string>RulesPreview</string>
<key>CFBundleName</key><string>Ares Rules Preview</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
if [[ "${1:-}" == "--open" ]]; then open "$APP"; fi
