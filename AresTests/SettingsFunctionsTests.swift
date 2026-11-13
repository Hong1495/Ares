import XCTest

final class SettingsFunctionsTests: XCTestCase {
    func testSavedSettingsReachConfiguration() throws {
        let name = "AresSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let values: [String: Any] = [DefaultsKeys.httpPort: "8902", DefaultsKeys.socksPort: "8901",
            DefaultsKeys.mixedPort: "8900", DefaultsKeys.tunMTU: 8000, DefaultsKeys.tunDevice: "utun9",
            DefaultsKeys.tunStack: "gvisor", DefaultsKeys.tunAutoRoute: false,
            DefaultsKeys.tunAutoDetectInterface: false, DefaultsKeys.keepAliveInterval: 30,
            DefaultsKeys.udpTimeout: 90, DefaultsKeys.allowLan: true, DefaultsKeys.ipv6: true,
            DefaultsKeys.logLevel: "debug", DefaultsKeys.dnsServers: "https://dns.example.com/dns-query, 1.1.1.1"]
        values.forEach { defaults.set($0.value, forKey: $0.key) }
        var config = ClashConfig(fromUserDefaults: true, defaults: defaults)
        XCTAssertEqual(config.tunMTU, 8000)
        XCTAssertEqual(config.tunDevice, "utun9")
        XCTAssertEqual(config.httpPort, 8902)
        XCTAssertEqual(config.socksPort, 8901)
        XCTAssertEqual(config.mixedPort, 8900)
        XCTAssertEqual(config.dnsServers, ["https://dns.example.com/dns-query", "1.1.1.1"])
        XCTAssertEqual(config.logLevel, "debug")
        XCTAssertFalse(config.toYAML().contains("\\/"))
        XCTAssertTrue(config.allowLan)
        XCTAssertTrue(config.ipv6)
        XCTAssertEqual(config.keepAliveInterval, 30)
        XCTAssertEqual(config.udpTimeout, 90)
        config.enableTun = true
        let yaml = config.toYAML()
        for item in ["mtu: 8000", "device: \"utun9\"", "stack: gvisor", "auto-route: false", "auto-detect-interface: false", "udp-timeout: 90", "mixed-port: 17890"] {
            XCTAssertTrue(yaml.contains(item), item)
        }
        // DoH hostnames need literal bootstrap resolvers, not themselves.
        XCTAssertTrue(yaml.contains("default-nameserver:\n    - 223.5.5.5"))
    }

    func testMissingDefaultsAndExplicitFalse() throws {
        let name = "AresSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        var config = ClashConfig(fromUserDefaults: true, defaults: defaults)
        XCTAssertEqual(config.tunMTU, 1400)
        XCTAssertTrue(config.tunAutoRoute)
        XCTAssertTrue(config.tunAutoDetectInterface)
        defaults.set(false, forKey: DefaultsKeys.tunAutoRoute)
        config = ClashConfig(fromUserDefaults: true, defaults: defaults)
        XCTAssertFalse(config.tunAutoRoute)
    }

    private func error(http: String = "7892", socks: String = "7891", mixed: String = "7890", mtu: Int = 1400,
                       keepAlive: Int = 15, ports: String = "80, 443", dns: String = "1.1.1.1", device: String = "") -> String? {
        SettingsValidation.error(http: http, socks: socks, mixed: mixed, mtu: mtu, keepAlive: keepAlive,
            udpTimeout: 120, mitmPorts: ports, dns: dns, device: device)
    }
    func testValidationRejectsInvalidAndConflictingValues() {
        XCTAssertNil(error())
        XCTAssertNotNil(error(http: "abc"))
        XCTAssertNotNil(error(http: "65536"))
        XCTAssertNotNil(error(http: "7890"))
        XCTAssertNotNil(error(mixed: "9097"))
        XCTAssertNotNil(error(mixed: "1053"))
        XCTAssertNotNil(error(mtu: 100))
        XCTAssertNotNil(error(keepAlive: 0))
        XCTAssertNotNil(error(ports: "80,"))
        XCTAssertNotNil(error(dns: ""))
        XCTAssertNotNil(error(dns: "1.1.1.1\nrules:"))
        XCTAssertNotNil(error(device: "en0"))
        XCTAssertNil(error(device: "utun9"))
    }
    func testBypassAndMITMIPRulesUseIPPredicates() {
        XCTAssertEqual(SettingsRouting.predicate(for: "127.*"), "IP-CIDR,127.0.0.0/8")
        XCTAssertEqual(SettingsRouting.predicate(for: "172.31.*"), "IP-CIDR,172.31.0.0/16")
        XCTAssertEqual(SettingsRouting.predicate(for: "192.168.1.1"), "IP-CIDR,192.168.1.1/32")
        XCTAssertEqual(SettingsRouting.predicate(for: "::1"), "IP-CIDR6,::1/128")
        XCTAssertEqual(SettingsRouting.predicate(for: "*.example.com"), "DOMAIN-SUFFIX,example.com")
        XCTAssertEqual(SettingsRouting.predicate(for: "172.16.0.0/12"), "IP-CIDR,172.16.0.0/12")
    }
}
