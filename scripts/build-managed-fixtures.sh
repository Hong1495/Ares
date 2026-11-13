#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PACKAGE="$ROOT/Packages/SubscriptionKit"
OUT="${1:?output directory required}"
mkdir -p "$OUT"
swift build --build-system native --package-path "$PACKAGE" >/dev/null
BIN="$(swift build --build-system native --package-path "$PACKAGE" --show-bin-path)"
OBJECTS=()
while IFS= read -r file; do OBJECTS+=("$file"); done < <(find "$BIN/Yams.build" "$BIN/CYaml.build" "$BIN/SubscriptionKit.build" -name '*.o')
xcrun swiftc -I "$BIN/Modules" -I "$PACKAGE/.build/checkouts/Yams/Sources/CYaml/include" "$ROOT/scripts/fixtures/ManagedComposer.swift" "${OBJECTS[@]}" -o "$OUT/compose"
python3 - "$OUT/source.json" <<'PY'
import json,sys
json.dump({'external-controller':'127.0.0.1:29451','mixed-port':29452,'fixture-port':29453,'fixture-upstream':29454,'bind-address':'127.0.0.1','allow-lan':False,'log-level':'silent','dns':{'enable':False},'tun':{'enable':False},'rules':['MATCH,DIRECT']},open(sys.argv[1],'w'))
PY
for mode in enabled disabled blocked; do "$OUT/compose" "$OUT/source.json" "$OUT/$mode.yaml" "$mode"; done
