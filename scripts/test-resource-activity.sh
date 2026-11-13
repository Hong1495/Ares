#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d /tmp/ares-resource-activity.XXXXXX)"
trap 'rm -rf "$OUT"' EXIT
xcrun swiftc -parse-as-library "$ROOT/Ares/Services/ResourceActivity.swift" "$ROOT/scripts/fixtures/ResourceActivityHarness.swift" -o "$OUT/check"
"$OUT/check"
