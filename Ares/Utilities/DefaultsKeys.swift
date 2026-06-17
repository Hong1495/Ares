import Foundation

enum DefaultsKeys {
    nonisolated static let silentStart = "silentStart"
    nonisolated static let autoStart = "autoStart"
    nonisolated static let systemProxyEnabled = "systemProxyEnabled"
    nonisolated static let tunEnabled = "tunEnabled"
    nonisolated static let bypassRules = "bypassRules"

    nonisolated static let mixedPort = "mixedPort"
    nonisolated static let socksPort = "socksPort"
    nonisolated static let httpPort = "httpPort"

    nonisolated static let logLevel = "logLevel"
    nonisolated static let activeProfileID = "activeProfileID"
    nonisolated static let theme = "theme"

    nonisolated static let tunStack = "tunStack"
    nonisolated static let tunMTU = "tunMTU"
    nonisolated static let tunDevice = "tunDevice"
    nonisolated static let tunAutoRoute = "tunAutoRoute"
    nonisolated static let tunAutoDetectInterface = "tunAutoDetectInterface"

    nonisolated static let allowLan = "allowLan"
    nonisolated static let ipv6 = "ipv6"
    nonisolated static let mitmEnabled = "mitmEnabled"
    nonisolated static let clashMode = "clashMode"

    nonisolated static let ideResilienceMode = "ideResilienceMode"
    nonisolated static let mitmHosts = "mitmHosts"
    nonisolated static let mitmPorts = "mitmPorts"
    nonisolated static let localRules = "localRules"
    nonisolated static let tlsFingerprint = "tlsFingerprint"
    nonisolated static let keepAliveInterval = "keepAliveInterval"
    nonisolated static let udpTimeout = "udpTimeout"
}
