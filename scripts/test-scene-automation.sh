#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d /tmp/ares-scene-automation.XXXXXX)"
trap 'rm -rf "$OUT"' EXIT
# Production scheduler, inert runtime/storage context, monitor disabled. No host network changes.
xcrun swiftc -parse-as-library "$ROOT/Ares/Utilities/SceneEnvironment.swift" "$ROOT/Ares/Utilities/ManualScenario.swift" \
  "$ROOT/Ares/Services/SceneAutomationService.swift" "$ROOT/scripts/fixtures/SceneAutomationHarness.swift" -o "$OUT/test"
"$OUT/test"
