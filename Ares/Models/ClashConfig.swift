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

    // External controller
    var externalController: String = "127.0.0.1:\(ClashPorts.apiNormal)"
    var secret: String = ""

    // TUN settings
    var enableTun: Bool = false
    var tunStack: String = "system"
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
    init(fromUserDefaults: Bool) {
        if fromUserDefaults {
            let defaults = UserDefaults.standard
            // Use current preferences or defaults
            // Note: Keys must match AppStorage in SettingsView
            // Fix: httpPort default should be 7892 to avoid conflict with mixedPort (7890)
            self.httpPort = Int(defaults.string(forKey: DefaultsKeys.httpPort) ?? "\(ClashPorts.defaultHttp)") ?? ClashPorts.defaultHttp
            self.socksPort = Int(defaults.string(forKey: DefaultsKeys.socksPort) ?? "\(ClashPorts.defaultSocks)") ?? ClashPorts.defaultSocks
            self.mixedPort = Int(defaults.string(forKey: DefaultsKeys.mixedPort) ?? "\(ClashPorts.defaultMixed)") ?? ClashPorts.defaultMixed // Default 7890
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

            // Check legacy keys or string/bool variants if needed?
            // SwiftUI AppStorage usually stores as the type defined.
            // But TextFields bound to String might store as String even if we want Int.

            self.allowLan = defaults.bool(forKey: DefaultsKeys.allowLan)
            self.ipv6 = defaults.bool(forKey: DefaultsKeys.ipv6)
            self.logLevel = defaults.string(forKey: DefaultsKeys.logLevel) ?? "info"
            self.mitmEnabled = defaults.bool(forKey: DefaultsKeys.mitmEnabled)

            // Mode is usually managed by AppState, but we load initial here
            if let modeStr = defaults.string(forKey: DefaultsKeys.clashMode), let m = Mode(rawValue: modeStr) {
                self.mode = m
            }

        }
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
        """

        // TUN configuration
        if enableTun {
            yaml += """

            # Performance Settings
            keep-alive-interval: 15
            find-process-mode: always
            tcp-concurrent: true
            udp-timeout: 120
            mptcp: false

            # TUN Mode Configuration
            tun:
              enable: true
              stack: \(tunStack)
              dns-hijack:
                - any:53
              auto-route: \(tunAutoRoute)
              auto-detect-interface: \(tunAutoDetectInterface)
            """

            // Only add our DNS config if subscription doesn't have one
            if !skipDNS {
                yaml += """

            # DNS Configuration (Fallback - subscription didn't provide)
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
                - 223.5.5.5
                - 119.29.29.29
                - 114.114.114.114
              fallback:
                - 1.1.1.1
                - 8.8.8.8
              fallback-filter:
                geoip: true
                geoip-code: CN
            """
            }

            // Only add our sniffer config if subscription doesn't have one
            if !skipSniffer {
                yaml += """

            # Sniffer Configuration (Fallback - subscription didn't provide)
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

        // NOTE: MITM integration is handled by ConfigService.injectMITMConfig()
        // to properly merge with profile's existing proxies/rules sections

        return yaml
    }
}
