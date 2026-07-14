import Foundation
import SystemConfiguration

/// System proxy configuration manager
class SystemProxyManager {
    static let shared = SystemProxyManager()

    struct ProxySnapshot: Codable {
        var webEnabled: Bool
        var secureWebEnabled: Bool
        var socksEnabled: Bool
        var webServer: String
        var webPort: String
        var secureWebServer: String
        var secureWebPort: String
        var socksServer: String
        var socksPort: String
        var bypassDomains: [String]
    }

    private let snapshotKey = "Ares.systemProxySnapshot.v1"
    
    private init() {}
    
    /// Set system proxy using networksetup command with administrator privileges
    /// This will prompt for password on each toggle
    /// Set system proxy using networksetup command
    /// Uses password-less sudo if available, otherwise prompts for password
    func setSystemProxy(enabled: Bool, httpPort: Int = ClashPorts.defaultMixed, socksPort: Int = ClashPorts.defaultSocks, bypassRules: String = "") async -> Bool {
        let bypassArray = bypassRules.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        
        // CRITICAL: Run ENTIRE operation on background thread (including getNetworkServicesSync)
        return await Task.detached {
            let services = await self.getNetworkServices()
            guard !services.isEmpty else {
                return false
            }

            let targetServices = await self.targetServices(from: services)

            if enabled {
                await self.saveSnapshotIfNeeded(for: targetServices)
            } else if await self.restoreSnapshot(for: targetServices) {
                return true
            }
            
            // --- 1. Try Direct Sudo (Password-less) ---
            if await PrivilegeService.shared.checkPrivileges() {
                for service in targetServices {
                    var commandsToRun: [[String]] = []
                    
                    if enabled {
                        commandsToRun.append(["-setwebproxy", service, "127.0.0.1", "\(httpPort)"])
                        commandsToRun.append(["-setsecurewebproxy", service, "127.0.0.1", "\(httpPort)"])
                        commandsToRun.append(["-setsocksfirewallproxy", service, "127.0.0.1", "\(socksPort)"])
                        commandsToRun.append(["-setwebproxystate", service, "on"])
                        commandsToRun.append(["-setsecurewebproxystate", service, "on"])
                        commandsToRun.append(["-setsocksfirewallproxystate", service, "on"])
                        
                        if !bypassArray.isEmpty {
                            commandsToRun.append(["-setproxybypassdomains", service] + bypassArray)
                        }
                    } else {
                        commandsToRun.append(["-setwebproxystate", service, "off"])
                        commandsToRun.append(["-setsecurewebproxystate", service, "off"])
                        commandsToRun.append(["-setsocksfirewallproxystate", service, "off"])
                    }
                    
                    for args in commandsToRun {
                        let task = Process()
                        task.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
                        task.arguments = ["-n", "/usr/sbin/networksetup"] + args
                        
                        try? task.run()
                        task.waitUntilExit()
                    }
                }
                
                if !enabled {
                    await self.clearSnapshot()
                }

                return true
            }
        
            // --- 2. Fallback to AppleScript (Password Prompt) ---
            var commands: [String] = []
            for service in targetServices {
                if enabled {
                    // Enable proxies
                    commands.append(Self.shellCommand(["/usr/sbin/networksetup", "-setwebproxy", service, "127.0.0.1", "\(httpPort)"]))
                    commands.append(Self.shellCommand(["/usr/sbin/networksetup", "-setsecurewebproxy", service, "127.0.0.1", "\(httpPort)"]))
                    commands.append(Self.shellCommand(["/usr/sbin/networksetup", "-setsocksfirewallproxy", service, "127.0.0.1", "\(socksPort)"]))
                    commands.append(Self.shellCommand(["/usr/sbin/networksetup", "-setwebproxystate", service, "on"]))
                    commands.append(Self.shellCommand(["/usr/sbin/networksetup", "-setsecurewebproxystate", service, "on"]))
                    commands.append(Self.shellCommand(["/usr/sbin/networksetup", "-setsocksfirewallproxystate", service, "on"]))

                    // Apply bypass rules
                    if !bypassArray.isEmpty {
                        commands.append(Self.shellCommand(["/usr/sbin/networksetup", "-setproxybypassdomains", service] + bypassArray))
                    }
                } else {
                    // Disable proxies
                    commands.append(Self.shellCommand(["/usr/sbin/networksetup", "-setwebproxystate", service, "off"]))
                    commands.append(Self.shellCommand(["/usr/sbin/networksetup", "-setsecurewebproxystate", service, "off"]))
                    commands.append(Self.shellCommand(["/usr/sbin/networksetup", "-setsocksfirewallproxystate", service, "off"]))
                }
            }

            let shellCommands = commands.joined(separator: " && ")
            let escapedShellCommands = AppleScriptEscaper.stringLiteral(shellCommands)
            let script = """
            do shell script "\(escapedShellCommands)" with administrator privileges
            """
            
            guard let appleScript = NSAppleScript(source: script) else {
                return false
            }
            
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            
            if let error = error {
                let message = String(describing: error)
                Task { @MainActor in
                    ClashViewModel.shared.addLog("[SystemProxy] AppleScript proxy update failed: \(message)", level: .debug)
                }
                return false
            }

            if !enabled {
                await self.clearSnapshot()
            }
            return true
        }.value
    }
    
    private static var cachedServices: [String] = []
    private static var lastCacheUpdate: Date = .distantPast

    nonisolated static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    nonisolated static func shellCommand(_ arguments: [String]) -> String {
        arguments.map(shellQuoted).joined(separator: " ")
    }
    
    /// Get list of network services (Wi-Fi, Ethernet, etc.)
    nonisolated private func getNetworkServices() async -> [String] {
        if let cached = await MainActor.run(body: {
            Date().timeIntervalSince(Self.lastCacheUpdate) < 30 ? Self.cachedServices : nil
        }) {
            return cached
        }
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        task.arguments = ["-listallnetworkservices"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                let lines = output.components(separatedBy: .newlines)
                    .dropFirst()
                    .filter { !$0.isEmpty && !$0.hasPrefix("*") }
                let services = Array(lines)
                await MainActor.run {
                    Self.cachedServices = services
                    Self.lastCacheUpdate = Date()
                }
                return services
            }
        } catch {}
        
        return await MainActor.run { Self.cachedServices.isEmpty ? ["Wi-Fi", "Ethernet"] : Self.cachedServices }
    }

    private func targetServices(from services: [String]) async -> [String] {
        let priorityServices = ["Wi-Fi", "Ethernet", "USB 10/100/1000 LAN"]
        let activeServices = services.filter { service in
            priorityServices.contains { service.contains($0) }
        }
        return activeServices.isEmpty ? services : activeServices
    }

    private func saveSnapshotIfNeeded(for services: [String]) async {
        if UserDefaults.standard.data(forKey: snapshotKey) != nil { return }

        var snapshots: [String: ProxySnapshot] = [:]
        for service in services {
            snapshots[service] = await readSnapshot(for: service)
        }

        if let data = try? JSONEncoder().encode(snapshots) {
            UserDefaults.standard.set(data, forKey: snapshotKey)
        }
    }

    private func clearSnapshot() async {
        UserDefaults.standard.removeObject(forKey: snapshotKey)
    }

    private func restoreSnapshot(for services: [String]) async -> Bool {
        guard let data = UserDefaults.standard.data(forKey: snapshotKey),
              let snapshots = try? JSONDecoder().decode([String: ProxySnapshot].self, from: data) else {
            return false
        }

        guard !snapshots.values.contains(where: snapshotUsesAresProxy) else {
            await clearSnapshot()
            return false
        }

        var allSucceeded = true
        for service in services {
            guard let snapshot = snapshots[service] else { continue }
            let commands = restoreCommands(for: service, snapshot: snapshot)
            for args in commands {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
                task.arguments = ["-n", "/usr/sbin/networksetup"] + args
                do {
                    try task.run()
                    task.waitUntilExit()
                    if task.terminationStatus != 0 { allSucceeded = false }
                } catch {
                    allSucceeded = false
                }
            }
        }

        if allSucceeded {
            await clearSnapshot()
        }
        return allSucceeded
    }

    private func readSnapshot(for service: String) async -> ProxySnapshot {
        async let web = readProxy(service: service, kind: "-getwebproxy")
        async let secure = readProxy(service: service, kind: "-getsecurewebproxy")
        async let socks = readProxy(service: service, kind: "-getsocksfirewallproxy")
        async let bypass = readBypassDomains(service: service)

        let webResult = await web
        let secureResult = await secure
        let socksResult = await socks

        return ProxySnapshot(
            webEnabled: webResult.enabled,
            secureWebEnabled: secureResult.enabled,
            socksEnabled: socksResult.enabled,
            webServer: webResult.server,
            webPort: webResult.port,
            secureWebServer: secureResult.server,
            secureWebPort: secureResult.port,
            socksServer: socksResult.server,
            socksPort: socksResult.port,
            bypassDomains: await bypass
        )
    }

    private func readProxy(service: String, kind: String) async -> (enabled: Bool, server: String, port: String) {
        let output = runNetworksetup([kind, service])
        var enabled = false
        var server = ""
        var port = "0"

        for line in output.components(separatedBy: .newlines) {
            let parts = line.components(separatedBy: ":")
            guard parts.count >= 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            let value = parts.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
            if key == "enabled" {
                enabled = value.lowercased() == "yes"
            } else if key == "server" {
                server = value
            } else if key == "port" {
                port = value
            }
        }

        return (enabled, server, port)
    }

    private func readBypassDomains(service: String) async -> [String] {
        let output = runNetworksetup(["-getproxybypassdomains", service])
        return output.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.localizedCaseInsensitiveContains("There aren't any bypass domains") }
    }

    private func runNetworksetup(_ args: [String]) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }

    private func runSudoNetworksetupSync(_ args: [String]) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        task.arguments = ["-n", "/usr/sbin/networksetup"] + args
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func restoreCommands(for service: String, snapshot: ProxySnapshot) -> [[String]] {
        var commands: [[String]] = []
        if !snapshot.webServer.isEmpty, snapshot.webPort != "0" {
            commands.append(["-setwebproxy", service, snapshot.webServer, snapshot.webPort])
        }
        if !snapshot.secureWebServer.isEmpty, snapshot.secureWebPort != "0" {
            commands.append(["-setsecurewebproxy", service, snapshot.secureWebServer, snapshot.secureWebPort])
        }
        if !snapshot.socksServer.isEmpty, snapshot.socksPort != "0" {
            commands.append(["-setsocksfirewallproxy", service, snapshot.socksServer, snapshot.socksPort])
        }

        commands.append(["-setwebproxystate", service, snapshot.webEnabled ? "on" : "off"])
        commands.append(["-setsecurewebproxystate", service, snapshot.secureWebEnabled ? "on" : "off"])
        commands.append(["-setsocksfirewallproxystate", service, snapshot.socksEnabled ? "on" : "off"])

        if !snapshot.bypassDomains.isEmpty {
            commands.append(["-setproxybypassdomains", service] + snapshot.bypassDomains)
        }

        return commands
    }
    
    /// Check if system proxy is currently enabled
    func isSystemProxyEnabled() -> Bool {
        guard let prefRef = SCPreferencesCreate(nil, "Ares" as CFString, nil),
              let sets = SCPreferencesGetValue(prefRef, kSCPrefNetworkServices) as? [String: Any] else {
            return false
        }
        
        for (key, value) in sets {
            guard let service = value as? [String: Any],
                  let hardware = service["Interface"] as? [String: Any],
                  let type = hardware["Type"] as? String,
                  type == "Ethernet" || type == "WiFi" || type == "AirPort" else {
                continue
            }
            
            let servicePath = "/\(kSCPrefNetworkServices)/\(key)/\(kSCEntNetProxies)" as CFString
            
            if let proxies = SCPreferencesPathGetValue(prefRef, servicePath) as? [String: Any],
               let httpEnabled = proxies[kSCPropNetProxiesHTTPEnable as String] as? Int,
               httpEnabled == 1 {
                return true
            }
        }
        
        return false
    }
    
    /// Synchronously disable all system proxies (for app termination)
    /// This method blocks and should ONLY be called during applicationWillTerminate
    @discardableResult
    func disableAllProxiesSync() -> Bool {
        let priorityServices = targetServicesSync(from: getNetworkServicesSync())

        if restoreSnapshotSync(for: priorityServices) {
            return true
        }

        var allSucceeded = true
        for service in priorityServices {
            let commands: [[String]] = [
                ["-setwebproxystate", service, "off"],
                ["-setsecurewebproxystate", service, "off"],
                ["-setsocksfirewallproxystate", service, "off"]
            ]
            
            for args in commands {
                if !runSudoNetworksetupSync(args) {
                    allSucceeded = false
                }
            }
        }

        return allSucceeded && proxiesAreDisabledSync(for: priorityServices)
    }

    private func getNetworkServicesSync() -> [String] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        task.arguments = ["-listallnetworkservices"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                let services = output.components(separatedBy: .newlines)
                    .dropFirst()
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty && !$0.hasPrefix("*") }
                if !services.isEmpty {
                    return Array(services)
                }
            }
        } catch {}

        return ["Wi-Fi", "Ethernet", "USB 10/100/1000 LAN"]
    }

    private func targetServicesSync(from services: [String]) -> [String] {
        let priorityServices = ["Wi-Fi", "Ethernet", "USB 10/100/1000 LAN"]
        let activeServices = services.filter { service in
            priorityServices.contains { service.contains($0) }
        }
        return activeServices.isEmpty ? services : activeServices
    }

    private func proxiesAreDisabledSync(for services: [String]) -> Bool {
        let proxyKinds = ["-getwebproxy", "-getsecurewebproxy", "-getsocksfirewallproxy"]
        return services.allSatisfy { service in
            proxyKinds.allSatisfy { kind in
                let output = runNetworksetup([kind, service])
                return output.components(separatedBy: .newlines).contains { line in
                    line.trimmingCharacters(in: .whitespacesAndNewlines)
                        .localizedCaseInsensitiveCompare("Enabled: No") == .orderedSame
                }
            }
        }
    }

    private func snapshotUsesAresProxy(_ snapshot: ProxySnapshot) -> Bool {
        let defaults = UserDefaults.standard
        let configuredMixedPort = defaults.string(forKey: DefaultsKeys.mixedPort) ?? "\(ClashPorts.defaultMixed)"
        let configuredSocksPort = defaults.string(forKey: DefaultsKeys.socksPort) ?? "\(ClashPorts.defaultSocks)"
        let aresPorts: Set<String> = [
            configuredMixedPort,
            configuredSocksPort,
            "\(ClashPorts.defaultMixed)",
            "\(ClashPorts.defaultSocks)",
            "\(ClashPorts.tunMixed)",
            "\(ClashPorts.tunSocks)"
        ]
        let loopbackHosts: Set<String> = ["127.0.0.1", "localhost", "::1"]

        let webIsAres = snapshot.webEnabled
            && loopbackHosts.contains(snapshot.webServer.lowercased())
            && aresPorts.contains(snapshot.webPort)
        let secureWebIsAres = snapshot.secureWebEnabled
            && loopbackHosts.contains(snapshot.secureWebServer.lowercased())
            && aresPorts.contains(snapshot.secureWebPort)
        let socksIsAres = snapshot.socksEnabled
            && loopbackHosts.contains(snapshot.socksServer.lowercased())
            && aresPorts.contains(snapshot.socksPort)

        return webIsAres || secureWebIsAres || socksIsAres
    }

    private func restoreSnapshotSync(for services: [String]) -> Bool {
        guard let data = UserDefaults.standard.data(forKey: snapshotKey),
              let snapshots = try? JSONDecoder().decode([String: ProxySnapshot].self, from: data) else {
            return false
        }

        guard !snapshots.values.contains(where: snapshotUsesAresProxy) else {
            UserDefaults.standard.removeObject(forKey: snapshotKey)
            return false
        }

        var restoredAnyService = false
        var allSucceeded = true

        for service in services {
            guard let snapshot = snapshots[service] else { continue }
            restoredAnyService = true
            for args in restoreCommands(for: service, snapshot: snapshot) {
                if !runSudoNetworksetupSync(args) {
                    allSucceeded = false
                }
            }
        }

        if restoredAnyService && allSucceeded {
            UserDefaults.standard.removeObject(forKey: snapshotKey)
            return true
        }

        return false
    }
}
