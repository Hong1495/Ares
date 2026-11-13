import Foundation
import SubscriptionKit
// A synthetic fixture transformer used by the native core harness. Never opens user profiles.
let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let source = try String(contentsOf: input, encoding: .utf8)
let root = try JSONSerialization.jsonObject(with: Data(source.utf8)) as! [String: Any]
let provider = (root["proxy-providers"] as! [String: [String: Any]])["Remote Nodes"]!
let url = (provider["health-check"] as! [String: Any])["url"] as! String
let edits = [
    "Pick": ["_create": "true", "type": "select", "proxies": try PolicyConfiguration.list(["Auto", "Fallback", "Balance"]), "use": try PolicyConfiguration.list(["Remote Nodes"])],
    "Auto": ["_create": "true", "type": "url-test", "use": try PolicyConfiguration.list(["Remote Nodes"]), "url": url, "interval": "600", "tolerance": "30"],
    "Fallback": ["_create": "true", "type": "fallback", "use": try PolicyConfiguration.list(["Remote Nodes"]), "url": url, "interval": "600"],
    "Balance": ["_create": "true", "type": "load-balance", "use": try PolicyConfiguration.list(["Remote Nodes"]), "url": url, "strategy": "round-robin"],
    "Fixture": ["_delete": "true"]
]
let rendered = try PolicyConfiguration.apply(source: source, overrides: PolicyConfiguration.encodeOverrides(edits))
try rendered.write(to: output, atomically: true, encoding: .utf8)
