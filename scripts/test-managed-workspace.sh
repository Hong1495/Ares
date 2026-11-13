#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d /tmp/ares-managed-test.XXXXXX)"
trap 'rm -rf "$OUT"' EXIT
PACKAGE="$ROOT/Packages/SubscriptionKit"
swift build --build-system native --package-path "$PACKAGE" >/dev/null
BIN="$(swift build --build-system native --package-path "$PACKAGE" --show-bin-path)"
OBJECTS=()
while IFS= read -r file; do OBJECTS+=("$file"); done < <(find "$BIN/Yams.build" "$BIN/CYaml.build" "$BIN/SubscriptionKit.build" -name '*.o')
xcrun swiftc -parse-as-library -I "$BIN/Modules" -I "$PACKAGE/.build/checkouts/Yams/Sources/CYaml/include" \
 "$ROOT/Ares/Services/ManagedWorkspaceService.swift" "$ROOT/scripts/fixtures/ManagedWorkspaceHarness.swift" "${OBJECTS[@]}" -o "$OUT/test"
"$OUT/test"
