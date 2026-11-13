#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d /tmp/ares-diagnostics.XXXXXX)"
trap 'rm -rf "$OUT"' EXIT
PACKAGE="$ROOT/Packages/SubscriptionKit"
swift build --build-system native --package-path "$PACKAGE" >/dev/null
BIN="$(swift build --build-system native --package-path "$PACKAGE" --show-bin-path)"
OBJECTS=()
while IFS= read -r file; do OBJECTS+=("$file"); done < <(find "$BIN/Yams.build" "$BIN/CYaml.build" "$BIN/SubscriptionKit.build" -name '*.o')
xcrun swiftc -parse-as-library -I "$BIN/Modules" -I "$PACKAGE/.build/checkouts/Yams/Sources/CYaml/include" \
  "$ROOT/Ares/Models/ProxyModels.swift" "$ROOT/Ares/Models/ProxyResourceModels.swift" "$ROOT/Ares/Models/RuleModels.swift" \
  "$ROOT/Ares/Utilities/RuntimeCheckpoint.swift" "$ROOT/Ares/Services/ActivityDiagnosticsService.swift" \
  "$ROOT/scripts/fixtures/ActivityDiagnosticsHarness.swift" "${OBJECTS[@]}" -o "$OUT/check"
"$OUT/check"
