#!/bin/bash
# Pure config integration tests; optional mihomo -t uses synthetic files in a temporary directory.
# Never starts a listener, changes routes, reads subscriptions, or contacts the running core.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PACKAGE="$ROOT/Packages/SubscriptionKit"
OUT="$(mktemp -d /tmp/ares-effective-config.XXXXXX)"
trap 'rm -rf "$OUT"' EXIT
swift build --build-system native --package-path "$PACKAGE" >/dev/null
BIN="$(swift build --build-system native --package-path "$PACKAGE" --show-bin-path)"
OBJECTS=()
while IFS= read -r file; do OBJECTS+=("$file"); done < <(find "$BIN/Yams.build" "$BIN/CYaml.build" "$BIN/SubscriptionKit.build" -name '*.o')
cat > "$OUT/main.swift" <<'SWIFT'
import Foundation
import SubscriptionKit
import Yams
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let name = "AresConfigIntegration.\(UUID().uuidString)"
let preferences = UserDefaults(suiteName: name)!
defer { preferences.removePersistentDomain(forName: name) }
let source = """
mixed-port: 9999
external-controller: 0.0.0.0:9998
find-process-mode: off
dns:
  enable: true
  enhanced-mode: redir-host
  nameserver: [1.1.1.1]
  nameserver-policy: {"+.internal": [192.0.2.53]}
tun:
  enable: true
  mtu: 8500
  route-exclude-address: [192.0.2.0/24]
sniffer: {enable: false}
proxies: []
proxy-groups: [{name: Automatic, type: url-test, proxies: [DIRECT], interval: 57}]
rules: ["MATCH,DIRECT"]
"""
let policyEdited = try PolicyConfiguration.apply(source: source, overrides: #"{"Automatic":{"interval":"99","tolerance":"35","timeout":"2000","lazy":"false"}}"#)
let policyRestored = try PolicyConfiguration.apply(source: source, overrides: "{}")
let editedGroups = try PolicyConfiguration.read(policyEdited)
precondition(editedGroups[0].fields["interval"] == "99")
let restoredGroups = try PolicyConfiguration.read(policyRestored)
precondition(restoredGroups[0].fields["interval"] == "57")
for tun in [false, true] {
    var config = ClashConfig(fromUserDefaults: true, defaults: preferences)
    config.enableTun = tun
    let merged = try EffectiveConfiguration.build(source: policyEdited, defaults: config.toYAML(),
        overrides: ProfileConfigMerge.overridePaths(defaults: preferences, tunEnabled: tun))
    let dns = try DNSConfiguration.apply(source: merged, overrides: #"{"hosts":"fixture.test: 192.0.2.1","fake-ip-filter":"['+.internal.test']","respect-rules":"false"}"#)
    var egress = EgressConfiguration.Overrides()
    egress.interface = "lo0"
    egress.listeners = "- {name: FixtureLocal, type: mixed, listen: 127.0.0.1, port: 28080, proxy: DIRECT, udp: true}"
    egress.tunnels = "- {network: [tcp, udp], address: '127.0.0.1:28081', target: '127.0.0.1:28082', proxy: DIRECT}"
    let text = try EgressConfiguration.apply(source: dns, overrides: EgressConfiguration.encode(egress))
    let node = try Yams.compose(yaml: text)!
    precondition(node["interface-name"]?.string == "lo0")
    let endpoints = try EgressConfiguration.endpoints(configuration: text)
    precondition(endpoints.count == 4)
    precondition(node["hosts"]?["fixture.test"]?.string == "192.0.2.1")
    precondition(node["tun"]?["enable"]?.bool == tun)
    precondition(node["tun"]?["mtu"]?.int == 8500)
    precondition(node["mixed-port"]?.int == (tun ? ClashPorts.tunMixed : ClashPorts.defaultMixed))
    precondition(node["find-process-mode"]?.string == "always")
    precondition(node["dns"]?["nameserver"]?.sequence?.first?.string == "1.1.1.1")
    precondition(node["dns"]?["fallback"] == nil)
    precondition(node["proxy-groups"]?.sequence?.first?["interval"]?.int == 99)
    try text.write(to: output.appendingPathComponent(tun ? "tun.yaml" : "normal.yaml"), atomically: true, encoding: .utf8)
}
preferences.set("9.9.9.9", forKey: DefaultsKeys.dnsServers)
let explicit = try EffectiveConfiguration.build(source: source,
    defaults: ClashConfig(fromUserDefaults: true, defaults: preferences).toYAML(),
    overrides: ProfileConfigMerge.overridePaths(defaults: preferences, tunEnabled: false))
let explicitNode = try Yams.compose(yaml: explicit)
precondition(explicitNode?["dns"]?["nameserver"]?.sequence?.first?.string == "9.9.9.9")
let change = NetworkPreferenceChange(proposed: [DefaultsKeys.dnsServers: "9.9.9.9"],
    displayed: [DefaultsKeys.dnsServers: "9.9.9.9"], defaults: preferences, removals: [DefaultsKeys.dnsServers])
change.apply(to: preferences)
let restored = try EffectiveConfiguration.build(source: source,
    defaults: ClashConfig(fromUserDefaults: true, defaults: preferences).toYAML(),
    overrides: ProfileConfigMerge.overridePaths(defaults: preferences, tunEnabled: false))
let restoredNode = try Yams.compose(yaml: restored)
precondition(restoredNode?["dns"]?["nameserver"]?.sequence?.first?.string == "1.1.1.1")
change.restore(in: preferences)
precondition(preferences.string(forKey: DefaultsKeys.dnsServers) == "9.9.9.9")
// Optional synthetic export for the disposable Linux VM. Never reads user profiles.
if let export = ProcessInfo.processInfo.environment["ARES_FLOW_FIXTURE_DIR"] {
    let dir = URL(fileURLWithPath: export)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let fixture = """
    dns: {enable: true, enhanced-mode: redir-host, nameserver: [1.1.1.1]}
    proxies:
      - {name: Node A, type: http, server: 127.0.0.1, port: 18081}
      - {name: Node B, type: http, server: 127.0.0.1, port: 18082}
    proxy-groups:
      - {name: Proxy, type: select, proxies: [Node A, Node B]}
    rules: ["MATCH,Proxy"]
    """
    for tun in [false, true] {
        var config = ClashConfig()
        config.enableTun = tun
        config.tunStack = "gvisor"
        config.tunDevice = "ares-test" // Linux-only fixture; never used by the macOS app.
        let yaml = try EffectiveConfiguration.build(source: fixture, defaults: config.toYAML(),
            overrides: ProfileConfigMerge.runtimePaths + (tun ? [["dns", "enable"]] : []))
        try yaml.write(to: dir.appendingPathComponent(tun ? "tun.yaml" : "normal.yaml"), atomically: true, encoding: .utf8)
    }
}
// Scene snapshots use the same preferences that the production builder reads.
let sceneProfile = UUID()
let beforeScene = ScenarioSettings.capture(profile: sceneProfile, defaults: preferences)
let scene = ScenarioSettings(localRules: "DOMAIN,scene.test,DIRECT", dns: #"{"hosts":"scene.test: 192.0.2.99"}"#,
    policy: #"{"Automatic":{"interval":"99"}}"#, egress: #"{"nodes":{},"interface":"lo0"}"#)
scene.install(profile: sceneProfile, defaults: preferences)
let captured = ScenarioSettings.capture(profile: sceneProfile, defaults: preferences)
let withPolicy = try PolicyConfiguration.apply(source: source, overrides: captured.policy!)
let withDNS = try DNSConfiguration.apply(source: withPolicy, overrides: captured.dns!)
let combined = try EgressConfiguration.apply(source: withDNS, overrides: captured.egress!)
let composed = try Yams.compose(yaml: combined)!
precondition(composed["hosts"]?["scene.test"]?.string == "192.0.2.99")
precondition(composed["proxy-groups"]?.sequence?.first?["interval"]?.int == 99)
precondition(composed["interface-name"]?.string == "lo0")
beforeScene.install(profile: sceneProfile, defaults: preferences)
precondition(ScenarioSettings.capture(profile: sceneProfile, defaults: preferences) == beforeScene)
print("Scene override composition and inheritance restoration passed.")
print("Effective config integration passed (normal, TUN, explicit preferences).")
SWIFT
xcrun swiftc -target arm64-apple-macosx14.0 \
  -I "$BIN/Modules" -I "$PACKAGE/.build/checkouts/Yams/Sources/CYaml/include" \
  "$ROOT/Ares/Utilities/SceneEnvironment.swift" "$ROOT/Ares/Utilities/SceneExecutionHistory.swift" "$ROOT/Ares/Utilities/ManualScenario.swift" "$ROOT/Ares/Models/ClashConfig.swift" "$ROOT/Ares/Utilities/ClashPorts.swift" \
  "$ROOT/Ares/Utilities/DefaultsKeys.swift" "$ROOT/Ares/Utilities/ProfileConfigMerge.swift" \
  "$OUT/main.swift" "${OBJECTS[@]}" -o "$OUT/check"
"$OUT/check" "$OUT"
if [[ -n "${1:-}" ]]; then
  CORE="$1"
  "$CORE" -v
  for MODE in normal tun; do
    mkdir "$OUT/$MODE"
    "$CORE" -t -d "$OUT/$MODE" -f "$OUT/$MODE.yaml"
  done
fi
