#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d /tmp/ares-config-api.XXXXXX)"
trap 'rm -rf "$OUT"' EXIT
# All HTTP is intercepted; no production controller lifecycle or core is linked.
xcrun swiftc -parse-as-library \
  "$ROOT/Ares/Models/DNSQueryResult.swift" "$ROOT/Ares/Services/ClashController+DNS.swift" \
  "$ROOT/Ares/Models/RuleModels.swift" \
  "$ROOT/Ares/Models/ClashConfig.swift" \
  "$ROOT/Ares/Utilities/ClashPorts.swift" \
  "$ROOT/Ares/Utilities/DefaultsKeys.swift" \
  "$ROOT/Ares/Utilities/CoreAPIContract.swift" \
  "$ROOT/Ares/Services/ClashController+Config.swift" \
  "$ROOT/scripts/fixtures/ConfigControllerHarness.swift" -o "$OUT/test"
"$OUT/test"
