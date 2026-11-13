#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d /tmp/ares-coordinator.XXXXXX)"
trap 'rm -rf "$OUT"' EXIT
PACKAGE="$ROOT/Packages/SubscriptionKit"
swift build --build-system native --package-path "$PACKAGE" >/dev/null
BIN="$(swift build --build-system native --package-path "$PACKAGE" --show-bin-path)"
OBJECTS=()
while IFS= read -r file; do OBJECTS+=("$file"); done < <(find "$BIN/Yams.build" "$BIN/CYaml.build" "$BIN/SubscriptionKit.build" -name '*.o')
# Production coordinator with inert services; never uses production files, processes or network.
xcrun swiftc -parse-as-library -I "$BIN/Modules" -I "$PACKAGE/.build/checkouts/Yams/Sources/CYaml/include" "$ROOT/Ares/Utilities/ClashPorts.swift" "$ROOT/Ares/Models/ClashConfig.swift" "$ROOT/Ares/Models/ProxyModels.swift" "$ROOT/Ares/Utilities/RuntimeCheckpoint.swift" \
  "$ROOT/Ares/Utilities/ConfigurationTransition.swift" "$ROOT/Ares/Services/ConfigurationCoordinator.swift" \
  "$ROOT/Ares/Utilities/DefaultsKeys.swift" "$ROOT/Ares/Services/LocalRulesService.swift" \
  "$ROOT/Ares/Services/PolicyGroupService.swift" "$ROOT/Ares/Services/DNSSettingsService.swift" "$ROOT/Ares/Services/EgressSettingsService.swift" "$ROOT/Ares/Utilities/SceneEnvironment.swift" "$ROOT/Ares/Utilities/SceneExecutionHistory.swift" "$ROOT/Ares/Utilities/ManualScenario.swift" "$ROOT/Ares/Services/ScenarioService.swift" \
  "$ROOT/scripts/fixtures/ConfigurationCoordinatorHarness.swift" "${OBJECTS[@]}" -o "$OUT/test"
"$OUT/test"
