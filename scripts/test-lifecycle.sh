#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d /tmp/ares-lifecycle.XXXXXX)"
trap 'rm -rf "$OUT"' EXIT
# Production wake/sleep logic with inert controller and state. No core or OS changes.
xcrun swiftc -parse-as-library "$ROOT/Ares/Utilities/CoreAPIContract.swift" \
  "$ROOT/Ares/Services/AppState+Lifecycle.swift" "$ROOT/scripts/fixtures/LifecycleHarness.swift" -o "$OUT/test"
"$OUT/test"
