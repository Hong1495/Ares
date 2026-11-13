#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d /tmp/ares-listener-check.XXXXXX)"
trap 'rm -rf "$OUT"' EXIT
PACKAGE="$ROOT/Packages/SubscriptionKit"
swift build --build-system native --package-path "$PACKAGE" >/dev/null
BIN="$(swift build --build-system native --package-path "$PACKAGE" --show-bin-path)"
OBJECTS=()
while IFS= read -r file; do OBJECTS+=("$file"); done < <(find "$BIN/Yams.build" "$BIN/CYaml.build" "$BIN/SubscriptionKit.build" -name '*.o')
cat > "$OUT/main.swift" <<'SWIFT'
import Foundation
import SubscriptionKit
@main struct Check {
    static func main() async throws {
        if CommandLine.arguments.count == 4 {
            try await ListenerVerification.verify(configuration: String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8), apiPort: Int(CommandLine.arguments[2])!, ownedPIDs: [Int32(CommandLine.arguments[3])!])
            print("PASS: production listener verifier against real owned sockets")
            return
        }
        let endpoints = [EgressConfiguration.Endpoint(transport: "tcp", host: "127.0.0.1", port: 1080), EgressConfiguration.Endpoint(transport: "udp", host: "::1", port: 1081)]
        let valid = "p321\nPTCP\nn127.0.0.1:9097\nPTCP\nn127.0.0.1:1080\nPUDP\nn[::1]:1081\n"
        precondition(ListenerVerification.matches(valid, endpoints: endpoints, apiPort: 9097))
        precondition(!ListenerVerification.matches(valid.replacingOccurrences(of: "n[::1]:1081", with: "n[::1]:1081->[::1]:5000"), endpoints: endpoints, apiPort: 9097))
        precondition(!ListenerVerification.matches(valid.replacingOccurrences(of: "PTCP\nn127.0.0.1:1080", with: "p999\nPTCP\nn127.0.0.1:1080"), endpoints: endpoints, apiPort: 9097))
        precondition(!ListenerVerification.matches(valid.replacingOccurrences(of: "PUDP", with: "PTCP"), endpoints: endpoints, apiPort: 9097))
        precondition(!ListenerVerification.matches(valid.replacingOccurrences(of: "127.0.0.1:1080", with: "*:1080"), endpoints: endpoints, apiPort: 9097))
        print("PASS: listener verification rejects wrong PID, transport, binding and connected outbound sockets")
    }
}
SWIFT
xcrun swiftc -parse-as-library -I "$BIN/Modules" -I "$PACKAGE/.build/checkouts/Yams/Sources/CYaml/include" \
  "$ROOT/Ares/Utilities/ProcessManager.swift" "$ROOT/Ares/Utilities/ListenerVerification.swift" \
  "$OUT/main.swift" "${OBJECTS[@]}" -o "$OUT/check"
"$OUT/check"
if [[ -n "${1:-}" ]]; then python3 "$ROOT/scripts/test-native-egress.py" "$1" "$OUT/check"; fi
