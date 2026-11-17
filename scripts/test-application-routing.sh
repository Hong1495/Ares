#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d /tmp/ares-application-routing.XXXXXX)"
trap 'rm -rf "$OUT"' EXIT
PACKAGE="$ROOT/Packages/SubscriptionKit"
swift build --build-system native --package-path "$PACKAGE" >/dev/null
BIN="$(swift build --build-system native --package-path "$PACKAGE" --show-bin-path)"
OBJECTS=()
while IFS= read -r file; do OBJECTS+=("$file"); done < <(find "$BIN/Yams.build" "$BIN/CYaml.build" "$BIN/SubscriptionKit.build" -name '*.o')
# Production presentation/view model with an inert routing service; no host writes or core.
xcrun swiftc -parse-as-library -I "$BIN/Modules" -I "$PACKAGE/.build/checkouts/Yams/Sources/CYaml/include" \
  "$ROOT/Ares/Models/Connection.swift" "$ROOT/Ares/Utilities/ConnectionIdentity.swift" \
  "$ROOT/Ares/Utilities/ApplicationRoutingPresentation.swift" "$ROOT/Ares/UI/ApplicationRoutingViewModel.swift" \
  "$ROOT/scripts/fixtures/ApplicationRoutingHarness.swift" "${OBJECTS[@]}" -o "$OUT/test"
"$OUT/test"
