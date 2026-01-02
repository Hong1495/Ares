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
    
    // MITM Integration (for TUN mode)
    var mitmEnabled: Bool = false
    var mitmPort: Int = 0
    
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
            
            # DNS Configuration (Critical for TUN mode speed)
            dns:
              enable: true
              listen: 0.0.0.0:1053
              ipv6: \(ipv6)
              enhanced-mode: fake-ip
              fake-ip-range: 198.18.0.1/16
              # CRITICAL: Exclude proxy server domains from fake-ip to prevent DNS loop
              fake-ip-filter:
                - "*.lan"
                - "*.local"
                - "*.localdomain"
                - "localhost"
                - "*.localhost"
                # Common proxy server domain patterns
                - "+.wgnmdgfw.com"
                - "+.ssr.gg"
                - "+.v2ray.com"
                - "+.trojan.com"
                - "+.node.com"
                - "+.proxy.com"
                - "*.airport.com"
                - "stun.*.*"
                - "stun.*.*.*"
                - "+.stun.*.*"
                - "+.stun.*.*.*"
                - "+.turn.*.*"
                - "+.turn.*.*.*"
              default-nameserver:
                - 223.5.5.5
                - 119.29.29.29
                - 1.1.1.1
                - 8.8.8.8
              nameserver:
                - https://doh.pub/dns-query
                - https://dns.alidns.com/dns-query
                - 223.5.5.5
                - 114.114.114.114
              fallback:
                - https://1.1.1.1/dns-query
                - https://8.8.8.8/dns-query
                - tls://8.8.4.4:853
                - tcp://8.8.8.8
              fallback-filter:
                geoip: true
                geoip-code: CN
                ipcidr:
                  - 240.0.0.0/4
              # CRITICAL: Proxy server domains must be resolved directly (not through proxy)
              # Otherwise TUN mode creates a DNS loop where proxy can't connect
              nameserver-policy:
                "+.wgnmdgfw.com": [223.5.5.5, 119.29.29.29]
                "+.ssr.gg": [223.5.5.5, 119.29.29.29]
                "+.v2ray.com": [223.5.5.5, 119.29.29.29]
                "+.trojan.com": [223.5.5.5, 119.29.29.29]
            
            # Sniffer Configuration (Recover domain names from TLS/HTTP)
            sniffer:
              enable: true
              force-domain:
                - "+"
              override-destination: true
              sniff:
                TLS:
                  ports: [443, 8443]
                HTTP:
                  ports: [80, 8080-8880]
                QUIC:
                  ports: [443, 8443]
            
            # TUN Mode Configuration
            tun:
              enable: true
              stack: \(tunStack)
              dns-hijack:
                - any:53
              auto-route: true
              auto-detect-interface: true
            """
        }
        
        // NOTE: MITM integration is handled by ConfigService.injectMITMConfig()
        // to properly merge with profile's existing proxies/rules sections
        
        return yaml
    }
}
