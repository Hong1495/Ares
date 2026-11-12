#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d /tmp/ares-safe-tests.XXXXXX)"
BUNDLE="$OUT/SafeFunctions.xctest"
mkdir -p "$BUNDLE/Contents/MacOS"
# Explicit allowlist. No app, delegate, singleton services, core executable,
# network transport, process/privilege manager, or certificate code is linked.
SOURCES=(
  "$ROOT/Ares/Utilities/ConfigDirectoryAccess.swift"
  "$ROOT/AresTests/ConfigDirectoryAccessTests.swift"
  "$ROOT/Ares/Utilities/CoreProcessIdentity.swift"
  "$ROOT/AresTests/CoreProcessIdentityTests.swift"
  "$ROOT/Ares/Utilities/NodeSelectionPlan.swift"
  "$ROOT/AresTests/NodeSelectionPlanTests.swift"
  "$ROOT/Ares/Utilities/ProfileConfigMerge.swift"
  "$ROOT/Ares/Utilities/ProxySnapshot.swift"
  "$ROOT/Ares/Models/ProxyModels.swift"
  "$ROOT/AresTests/ProfileConfigMergeTests.swift"
  "$ROOT/AresTests/ProxySnapshotTests.swift"
  "$ROOT/Ares/Utilities/AppleScriptEscaper.swift"
  "$ROOT/Ares/Utilities/CoreAPIContract.swift"
  "$ROOT/Ares/Utilities/ProxyTransaction.swift"
  "$ROOT/Ares/Utilities/RuntimeTransition.swift"
  "$ROOT/Ares/Utilities/ListenerMigration.swift"
  "$ROOT/Ares/Utilities/SubscriptionPayload.swift"
  "$ROOT/Ares/Services/SubscriptionConverter.swift"
  "$ROOT/AresTests/FunctionalContractTests.swift"
  "$ROOT/AresTests/ProcessOwnershipSourceTests.swift"
  "$ROOT/AresTests/AppUpdateSourceTests.swift"
  "$ROOT/Ares/Utilities/CoreReleaseSelector.swift"
  "$ROOT/Ares/Services/MITMDomainMatcher.swift"
  "$ROOT/AresTests/AppleScriptEscaperTests.swift"
  "$ROOT/AresTests/CoreReleaseSelectorTests.swift"
  "$ROOT/AresTests/MITMDomainMatcherTests.swift"
  "$ROOT/AresTests/AppStateTUNSourceTests.swift"
  "$ROOT/AresTests/SystemProxyManagerSourceTests.swift"
  "$ROOT/AresTests/SystemProxyTerminationSourceTests.swift"
  "$ROOT/AresTests/SettingsViewSourceTests.swift"
  "$ROOT/AresTests/SubscriptionConverterTests.swift"
)
DEVELOPER_DIR_PATH="$(xcode-select -p)"
PLATFORM="$DEVELOPER_DIR_PATH/Platforms/MacOSX.platform/Developer"
xcrun swiftc -emit-library -module-name SafeFunctions \
  -framework XCTest -lXCTestSwiftSupport \
  -L "$PLATFORM/usr/lib" -F "$PLATFORM/Library/Frameworks" -I "$PLATFORM/usr/lib" \
  -Xlinker -rpath -Xlinker "$PLATFORM/Library/Frameworks" \
  -Xlinker -rpath -Xlinker "$PLATFORM/usr/lib" \
  "${SOURCES[@]}" -o "$BUNDLE/Contents/MacOS/SafeFunctions" \
  > "$OUT/compile.log" 2>&1 || { cat "$OUT/compile.log"; exit 1; }
xcrun xctest "$BUNDLE" > "$OUT/results.log" 2>&1 || { cat "$OUT/results.log"; exit 1; }
cat "$OUT/results.log"
printf '\nLogs: %s\n' "$OUT"

# Pure YAML parsing package: no production services or core are linked.
swift test --package-path "$ROOT/Packages/SubscriptionKit"
