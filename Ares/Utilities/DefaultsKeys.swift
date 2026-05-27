import Foundation

enum DefaultsKeys {
    static let silentStart = "silentStart"
    static let autoStart = "autoStart"
    static let systemProxyEnabled = "systemProxyEnabled"
    static let tunEnabled = "tunEnabled"
    static let bypassRules = "bypassRules"

    static let mixedPort = "mixedPort"
    static let socksPort = "socksPort"
    static let httpPort = "httpPort"

    static let logLevel = "logLevel"
    static let activeProfileID = "activeProfileID"
    static let theme = "theme"

    static let tunStack = "tunStack"
    static let tunMTU = "tunMTU"
    static let tunDevice = "tunDevice"
    static let tunAutoRoute = "tunAutoRoute"
    static let tunAutoDetectInterface = "tunAutoDetectInterface"

    static let allowLan = "allowLan"
    static let ipv6 = "ipv6"
    static let mitmEnabled = "mitmEnabled"
    static let clashMode = "clashMode"

    static let ideResilienceMode = "ideResilienceMode"
    static let mitmHosts = "mitmHosts"
    static let mitmPorts = "mitmPorts"
    static let localRules = "localRules"
    static let tlsFingerprint = "tlsFingerprint"
    static let keepAliveInterval = "keepAliveInterval"
    static let udpTimeout = "udpTimeout"
}
