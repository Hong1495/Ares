#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d /tmp/ares-proxy-tests.XXXXXX)"
trap 'rm -rf "$OUT"' EXIT
# Fake URLProtocol intercepts every request; no real core or network is used.
xcrun swiftc -parse-as-library \
  "$ROOT/Ares/Services/ResourceActivity.swift" \
  "$ROOT/Ares/Models/ProxyResourceModels.swift" \
  "$ROOT/Ares/Models/ProxyModels.swift" \
  "$ROOT/Ares/Utilities/ProxySnapshot.swift" \
  "$ROOT/Ares/Utilities/CoreAPIContract.swift" \
  "$ROOT/Ares/Services/ClashController+Resources.swift" \
  "$ROOT/Ares/Services/ClashController+Proxies.swift" \
  "$ROOT/scripts/fixtures/ProxyControllerHarness.swift" -o "$OUT/test"
"$OUT/test"
