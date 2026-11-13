import Foundation
import Yams

/// Explicit authenticated proxy access, not discovery or transparent LAN routing.
public enum DeviceAccess {
    public struct Device: Codable, Equatable, Identifiable, Sendable {
        public var id: UUID
        public var name: String
        public var enabled: Bool
        public var address: String
        public var port: Int
        public var username: String
        public var password: String
        public var target: String
        public init(id: UUID = UUID(), name: String = "", enabled: Bool = false, address: String = "127.0.0.1", port: Int = 10810, username: String = "", password: String = "", target: String = "DIRECT") {
            self.id = id; self.name = name; self.enabled = enabled; self.address = address; self.port = port
            self.username = username; self.password = password; self.target = target
        }
        public var listenerName: String { "Ares Device " + id.uuidString }
    }
    public static func validate(_ devices: [Device]) throws {
        guard Set(devices.map(\.id)).count == devices.count, Set(devices.map(\.name)).count == devices.count else { throw ManagedResources.Failure.invalid("Device names must be unique.") }
        for device in devices {
            guard !device.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, device.name.count <= 100,
                  EgressConfiguration.isIP(device.address), !["0.0.0.0", "::"].contains(device.address),
                  (1024...65535).contains(device.port), !device.username.isEmpty, !device.username.contains(":"),
                  !device.username.contains(where: { $0.isWhitespace }), device.password.count >= 16,
                  !device.password.contains(where: { $0.isNewline }), !device.target.isEmpty else {
                throw ManagedResources.Failure.invalid("Use a device name, a specific local IP, port 1024–65535, username and password of at least 16 characters.")
            }
        }
        let enabled = devices.filter(\.enabled)
        guard Set(enabled.map(\.port)).count == enabled.count else { throw ManagedResources.Failure.invalid("Each enabled device needs a separate port.") }
    }
    public static func apply(source: String, devices: [Device]) throws -> String {
        try validate(devices)
        guard devices.contains(where: \.enabled) else { return source }
        var root = try ManagedResources.document(source)
        let targets = Set(try EgressConfiguration.read(source).targets + ["REJECT"])
        var listeners = Array(root["listeners"]?.sequence ?? [])
        for device in devices where device.enabled {
            guard targets.contains(device.target) else { throw ManagedResources.Failure.invalid("A device route no longer exists. Choose another route before applying.") }
            guard !listeners.contains(where: { $0["name"]?.string == device.listenerName }) else { throw ManagedResources.Failure.invalid("Device listener name conflicts with an existing listener.") }
            let node: Node = ["name": Node(device.listenerName, Tag(.str)), "type": "mixed", "listen": Node(device.address, Tag(.str)),
                              "port": Node(String(device.port), Tag(.int)), "udp": Node("false", Tag(.bool)),
                              "proxy": Node(device.target, Tag(.str)),
                              "users": [["username": Node(device.username, Tag(.str)), "password": Node(device.password, Tag(.str))]]]
            listeners.append(node)
        }
        root["listeners"] = .sequence(.init(listeners))
        let result = try ManagedResources.yaml(root)
        try EgressConfiguration.validatePorts(configuration: result)
        return result
    }
}
