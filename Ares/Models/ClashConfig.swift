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
    var mixedPort: Int = 7890  // 改为 7890
    var socksPort: Int = 7891  // 改为 7891
    var httpPort: Int = 7892   // 改为 7892
    
    // Core settings
    var mode: Mode = .rule
    var logLevel: String = "info"
    var allowLan: Bool = false
    var ipv6: Bool = true
    
    // External controller
    var externalController: String = "127.0.0.1:9097"
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
            self.httpPort = Int(defaults.string(forKey: "httpPort") ?? "7892") ?? 7892
            self.socksPort = Int(defaults.string(forKey: "socksPort") ?? "7891") ?? 7891
            self.mixedPort = Int(defaults.string(forKey: "mixedPort") ?? "7890") ?? 7890 // Default 7890
            self.tunStack = defaults.string(forKey: "tunStack") ?? "system"
            self.tunAutoRoute = defaults.bool(forKey: "tunAutoRoute")
            self.tunAutoDetectInterface = defaults.bool(forKey: "tunAutoDetectInterface")
            // Handle case where keys don't exist (default to true)
            if defaults.object(forKey: "tunAutoRoute") == nil {
                self.tunAutoRoute = true
            }
            if defaults.object(forKey: "tunAutoDetectInterface") == nil {
                self.tunAutoDetectInterface = true
            }
            
            // Check legacy keys or string/bool variants if needed? 
            // SwiftUI AppStorage usually stores as the type defined.
            // But TextFields bound to String might store as String even if we want Int.
            
            self.allowLan = defaults.bool(forKey: "allowLan")
            self.ipv6 = defaults.bool(forKey: "ipv6")
            self.logLevel = defaults.string(forKey: "logLevel") ?? "info"
            
            // Mode is usually managed by AppState, but we load initial here
            if let modeStr = defaults.string(forKey: "clashMode"), let m = Mode(rawValue: modeStr) {
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
            actualMixedPort = 17890
            actualSocksPort = 17891
            actualHttpPort = 17892
            actualController = "127.0.0.1:19097"
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
