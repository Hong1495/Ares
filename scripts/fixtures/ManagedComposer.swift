import Foundation
import SubscriptionKit
let args = CommandLine.arguments
let source = try String(contentsOfFile: args[1], encoding: .utf8)
let output = URL(fileURLWithPath: args[2])
let root = try JSONSerialization.jsonObject(with: Data(source.utf8)) as! [String: Any]
let port = root["fixture-port"] as! Int
var resources = ManagedResources.Draft()
resources.nodes["Local"] = "type: http\nserver: 127.0.0.1\nport: \(root["fixture-upstream"] as! Int)"
resources.providers["Pool"] = "type: inline\npayload: [{name: Inline, type: http, server: 127.0.0.1, port: \(root["fixture-upstream"] as! Int)}]"
let policy = try PolicyConfiguration.encodeOverrides(["Managed": ["_create": "true", "type": "select", "proxies": "[\"Local\"]", "use": "[\"Pool\"]"]])
let rendered = try PolicyConfiguration.apply(source: ManagedResources.apply(source: source, draft: resources), overrides: policy)
let device = DeviceAccess.Device(id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, name: "Fixture", enabled: args.count < 4 || args[3] != "disabled", address: "127.0.0.1", port: port, username: "fixture", password: "fixture-only-password", target: args.count > 3 && args[3] == "blocked" ? "REJECT" : "Managed")
try DeviceAccess.apply(source: rendered, devices: [device]).write(to: output, atomically: true, encoding: .utf8)
