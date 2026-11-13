#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d /tmp/ares-quality.XXXXXX)"
trap 'rm -rf "$OUT"' EXIT
PACKAGE="$ROOT/Packages/SubscriptionKit"
swift build --build-system native --package-path "$PACKAGE" >/dev/null
BIN="$(swift build --build-system native --package-path "$PACKAGE" --show-bin-path)"
OBJECTS=()
while IFS= read -r file; do OBJECTS+=("$file"); done < <(find "$BIN/Yams.build" "$BIN/CYaml.build" "$BIN/SubscriptionKit.build" -name '*.o')
xcrun swiftc -parse-as-library -I "$BIN/Modules" -I "$PACKAGE/.build/checkouts/Yams/Sources/CYaml/include" \
  "$ROOT/Ares/Utilities/CoreAPIContract.swift" "$ROOT/Ares/Models/DNSQueryResult.swift" "$ROOT/Ares/Models/ProxyModels.swift" \
  "$ROOT/Ares/Services/NetworkQualityService.swift" "$ROOT/scripts/fixtures/NetworkQualityHarness.swift" "${OBJECTS[@]}" -o "$OUT/test"
"$OUT/test"
