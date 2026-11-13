import Foundation

/// Clash core configuration model
struct ClashConfig: Codable {
    // Modes
    enum Mode: String, Codable, CaseIterable {
        case rule = "rule"
        case global = "global"
        case direct = "direct"
    }

    // Ports (避免与 Clash Verge 冲突)
    var mixedPort: Int = ClashPorts.defaultMixed  // 改为 7890
    var socksPort: Int = ClashPorts.defaultSocks  // 改为 7891
    var httpPort: Int = ClashPorts.defaultHttp   // 改为 7892

    // Core settings
    var mode: Mode = .rule
    var logLevel: String = "info"
    var allowLan: Bool = false
    var ipv6: Bool = true
    var dnsServers: [String] = ["223.5.5.5", "119.29.29.29"]

    // External controller
    var externalController: String = "127.0.0.1:\(ClashPorts.apiNormal)"
    var secret: String = ""

    // TUN settings
    var enableTun: Bool = false
    var tunStack: String = "system"
    var tunMTU: Int = 1400
    var tunDevice: String = ""
    var keepAliveInterval: Int = 15
    var udpTimeout: Int = 120
    var tunAutoRoute: Bool = true
    var tunAutoDetectInterface: Bool = true
    var mptcp: Bool = false

    // MITM Integration (for TUN mode)
    var mitmEnabled: Bool = false
    var mitmPort: Int = 0

    // Config skip flags (preserve subscription's optimized config)
    var skipDNS: Bool = false
    var skipSniffer: Bool = false



    /// Initialize with default values

    /// Initialize with default values
    init() {}

    /// Initialize from UserDefaults
    init(fromUserDefaults: Bool, defaults: UserDefaults = .standard) {
        if fromUserDefaults {
            // Use current preferences or defaults
            // Note: Keys must match AppStorage in SettingsView
            // Fix: httpPort default should be 7892 to avoid conflict with mixedPort (7890)
            self.httpPort = Int(defaults.string(forKey: DefaultsKeys.httpPort) ?? "\(ClashPorts.defaultHttp)") ?? ClashPorts.defaultHttp
            self.socksPort = Int(defaults.string(forKey: DefaultsKeys.socksPort) ?? "\(ClashPorts.defaultSocks)") ?? ClashPorts.defaultSocks
            self.mixedPort = Int(defaults.string(forKey: DefaultsKeys.mixedPort) ?? "\(ClashPorts.defaultMixed)") ?? ClashPorts.defaultMixed // Default 7890
            self.tunMTU = defaults.object(forKey: DefaultsKeys.tunMTU) == nil ? 1400 : defaults.integer(forKey: DefaultsKeys.tunMTU)
            self.tunDevice = defaults.string(forKey: DefaultsKeys.tunDevice) ?? ""
            self.tunStack = defaults.string(forKey: DefaultsKeys.tunStack) ?? "system"
            self.tunAutoRoute = defaults.bool(forKey: DefaultsKeys.tunAutoRoute)
            self.tunAutoDetectInterface = defaults.bool(forKey: DefaultsKeys.tunAutoDetectInterface)
            // Handle case where keys don't exist (default to true)
            if defaults.object(forKey: DefaultsKeys.tunAutoRoute) == nil {
                self.tunAutoRoute = true
            }
            if defaults.object(forKey: DefaultsKeys.tunAutoDetectInterface) == nil {
                self.tunAutoDetectInterface = true
            }

            self.keepAliveInterval = defaults.integer(forKey: DefaultsKeys.keepAliveInterval)
            self.udpTimeout = defaults.integer(forKey: DefaultsKeys.udpTimeout)

            if defaults.object(forKey: DefaultsKeys.keepAliveInterval) == nil {
                self.keepAliveInterval = 15
            }
            if defaults.object(forKey: DefaultsKeys.udpTimeout) == nil {
                self.udpTimeout = 120
            }

            // Check legacy keys or string/bool variants if needed?
            // SwiftUI AppStorage usually stores as the type defined.
            // But TextFields bound to String might store as String even if we want Int.

            self.allowLan = defaults.bool(forKey: DefaultsKeys.allowLan)
            self.ipv6 = defaults.bool(forKey: DefaultsKeys.ipv6)
            self.logLevel = defaults.string(forKey: DefaultsKeys.logLevel) ?? "info"
            self.mitmEnabled = defaults.bool(forKey: DefaultsKeys.mitmEnabled)
            let savedDNSServers = (defaults.string(forKey: DefaultsKeys.dnsServers) ?? "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !savedDNSServers.isEmpty {
                self.dnsServers = savedDNSServers
            }

            // Mode is usually managed by AppState, but we load initial here
            if let modeStr = defaults.string(forKey: DefaultsKeys.clashMode), let m = Mode(rawValue: modeStr) {
                self.mode = m
            }

        }
    }

    private func yamlString(_ value: String) -> String {
        // JSON strings are valid YAML scalars, including quotes and punctuation.
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        return String(data: try! encoder.encode(value), encoding: .utf8)!
    }

    /// Generate YAML representation for config.yaml
    func toYAML() -> String {
        // Port isolation: TUN mode uses different ports to avoid TIME_WAIT conflicts
        let actualMixedPort: Int
        let actualSocksPort: Int
        let actualHttpPort: Int
        let actualController: String

        if enableTun {
            // TUN mode uses isolated ports to avoid TIME_WAIT conflicts when switching modes
            // This ensures clean port release when toggling between TUN and Normal
            actualMixedPort = ClashPorts.tunMixed
            actualSocksPort = ClashPorts.tunSocks
            actualHttpPort = ClashPorts.tunHttp
            actualController = "127.0.0.1:\(ClashPorts.apiTun)"
        } else {
            // Normal mode uses user-configured ports
            actualMixedPort = mixedPort
            actualSocksPort = socksPort
            actualHttpPort = httpPort
            actualController = externalController
        }

        var yaml = """
        # Ares Clash Configuration
        mixed-port: \(actualMixedPort)
        socks-port: \(actualSocksPort)
        port: \(actualHttpPort)
        mode: \(mode.rawValue)
        log-level: \(logLevel)
        allow-lan: \(allowLan)
        ipv6: \(ipv6)
        external-controller: \(actualController)
        secret: "\(secret)"

        # Profile Settings - Enable proxy selection persistence
        profile:
          store-selected: true
          store-fake-ip: true

        # Performance Settings (always on; find-process-mode required for Activity feature)
        keep-alive-interval: \(keepAliveInterval)
        find-process-mode: always
        tcp-concurrent: true
        udp-timeout: \(udpTimeout)
        mptcp: false
        """

        // TUN configuration
        if enableTun {
            yaml += """

            # TUN Mode Configuration
            tun:
              enable: true
              stack: \(tunStack)
              mtu: \(tunMTU)
              dns-hijack:
                - any:53
              auto-route: \(tunAutoRoute)
              auto-detect-interface: \(tunAutoDetectInterface)
            """

            // Add device if specified
            if !tunDevice.isEmpty {
                yaml += """

              device: \(yamlString(tunDevice))
            """
            }

            // Only add our sniffer config if subscription doesn't have one
            if !skipSniffer {
                yaml += """

            # Sniffer Configuration
            sniffer:
              enable: true
              sniff:
                TLS:
                  ports: [443, 8443]
                HTTP:
                  ports: [80, 8080-8880]
            """
            }
        }

        if !enableTun {
            yaml += "\ntun:\n  enable: false\n"
        }

        // The DNS settings are shared by normal and TUN configurations.
        if !skipDNS {
            let dnsEntries = dnsServers.map { "    - \(yamlString($0))" }.joined(separator: "\n")
            yaml += """

            # DNS Configuration
            dns:
              enable: true
              listen: 0.0.0.0:1053
              ipv6: \(ipv6)
              enhanced-mode: fake-ip
              fake-ip-range: 198.18.0.1/16
              fake-ip-filter:
                - "*.lan"
                - "*.local"
                - "*.localdomain"
                - "localhost"
                - "*.localhost"
              default-nameserver:
                - 223.5.5.5
                - 119.29.29.29
              nameserver:
            \(dnsEntries)
              fallback:
                - https://dns.alidns.com/dns-query
                - https://doh.pub/dns-query
              fallback-filter:
                geoip: true
                geoip-code: CN
                geosite:
                  - geolocation-!cn
                ipcidr:
                  - 240.0.0.0/4
            """
        }

        // NOTE: MITM integration is handled by ConfigService.injectMITMConfig()
        // to properly merge with profile's existing proxies/rules sections

        return yaml
    }
}
