import Foundation
import SystemConfiguration

/// System proxy configuration manager
@MainActor
class SystemProxyManager {
    static let shared = SystemProxyManager()

    struct ProxySnapshot: Codable, Equatable {
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
    
    private var isUpdating = false
    private(set) var lastError: String?

    func setSystemProxy(enabled: Bool, httpPort: Int = ClashPorts.defaultMixed, socksPort: Int = ClashPorts.defaultSocks, bypassRules: String = "") async -> Bool {
        guard !isUpdating else { return false }
        isUpdating = true
        defer { isUpdating = false }
        lastError = nil
        let services = await targetServices(from: getNetworkServices())
        guard !services.isEmpty else { lastError = "Cannot read network services"; return false }
        if !enabled {
            let restored = await restoreSnapshot(for: getNetworkServices())
            if !restored { lastError = "Could not verify restoration. The saved network baseline has been retained." }
            return restored
        }
        guard (1...65535).contains(httpPort), (1...65535).contains(socksPort),
              let before = await readSnapshots(for: services) else {
            lastError = "Cannot read a complete network baseline"
            return false
        }
        let createdBaseline = UserDefaults.standard.data(forKey: snapshotKey) == nil
        if createdBaseline {
            guard let data = try? JSONEncoder().encode(before) else { return false }
            UserDefaults.standard.set(data, forKey: snapshotKey)
        } else {
            guard var saved = loadSnapshot() else {
                lastError = "Saved network baseline is unreadable"
                return false
            }
            // Newly connected services need their own baseline before the first mutation.
            for (service, snapshot) in before where saved[service] == nil { saved[service] = snapshot }
            guard let data = try? JSONEncoder().encode(saved) else { return false }
            UserDefaults.standard.set(data, forKey: snapshotKey)
        }
        let bypass = bypassRules.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let desired = Dictionary(uniqueKeysWithValues: services.map { service in
            (service, ProxySnapshot(webEnabled: true, secureWebEnabled: true, socksEnabled: true,
                webServer: "127.0.0.1", webPort: "\(httpPort)", secureWebServer: "127.0.0.1",
                secureWebPort: "\(httpPort)", socksServer: "127.0.0.1", socksPort: "\(socksPort)", bypassDomains: bypass))
        })
        let useSudo = await PrivilegeService.shared.checkPrivileges()
        let result = await ProxyTransaction.apply(
            write: { await self.writeSnapshots(desired, useSudo: useSudo) },
            verify: { await self.matches(desired) },
            rollback: { await self.writeSnapshots(before, useSudo: useSudo) },
            verifyRollback: { await self.matches(before) })
        switch result {
        case .committed: return true
        case .rolledBack:
            if createdBaseline { UserDefaults.standard.removeObject(forKey: snapshotKey) }
            lastError = "Proxy update failed; the state before this operation was restored."
        case .recoveryRequired: lastError = "Proxy update and recovery could not be verified. Keep the core running and check network settings."
        }
        return false
    }

    private func loadSnapshot() -> [String: ProxySnapshot]? {
        guard let data = UserDefaults.standard.data(forKey: snapshotKey),
              let snapshots = try? JSONDecoder().decode([String: ProxySnapshot].self, from: data),
              !snapshots.isEmpty else { return nil }
        return snapshots
    }

    private func readSnapshots(for services: [String]) async -> [String: ProxySnapshot]? {
        var result: [String: ProxySnapshot] = [:]
        for service in services {
            guard let snapshot = readSnapshotSync(for: service) else { return nil }
            result[service] = snapshot
        }
        return result
    }

    private func writeSnapshots(_ snapshots: [String: ProxySnapshot], useSudo: Bool) async -> Bool {
        let commands = snapshots.keys.sorted().flatMap { restoreCommands(for: $0, snapshot: snapshots[$0]!) }
        if useSudo {
            let runner = ProcessManager()
            for args in commands {
                guard let result = try? await runner.run(executable: "/usr/bin/sudo", arguments: ["-n", "/usr/sbin/networksetup"] + args, timeout: 10), result.exitCode == 0 else { return false }
            }
            return true
        }
        let shellCommands = commands.map { Self.shellCommand(["/usr/sbin/networksetup"] + $0) }.joined(separator: " && ")
        let escaped = AppleScriptEscaper.stringLiteral(shellCommands)
        guard let script = NSAppleScript(source: "do shell script \"\(escaped)\" with administrator privileges") else { return false }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        return error == nil
    }

    private func matches(_ snapshots: [String: ProxySnapshot]) async -> Bool {
        snapshots.allSatisfy { service, expected in
            guard let actual = readSnapshotSync(for: service) else { return false }
            return equivalent(actual, expected)
        }
    }

    // Disabled endpoints do not carry traffic; networksetup cannot clear their stored address.
    private func equivalent(_ actual: ProxySnapshot, _ expected: ProxySnapshot) -> Bool {
        actual.webEnabled == expected.webEnabled && actual.secureWebEnabled == expected.secureWebEnabled && actual.socksEnabled == expected.socksEnabled
        && (!expected.webEnabled || (actual.webServer == expected.webServer && actual.webPort == expected.webPort))
        && (!expected.secureWebEnabled || (actual.secureWebServer == expected.secureWebServer && actual.secureWebPort == expected.secureWebPort))
        && (!expected.socksEnabled || (actual.socksServer == expected.socksServer && actual.socksPort == expected.socksPort))
        && Set(actual.bypassDomains) == Set(expected.bypassDomains)
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
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else { return [] }
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
        
        return []
    }

    private func targetServices(from services: [String]) async -> [String] {
        let priorityServices = ["Wi-Fi", "Ethernet", "USB 10/100/1000 LAN"]
        let activeServices = services.filter { service in
            priorityServices.contains { service.contains($0) }
        }
        return activeServices.isEmpty ? services : activeServices
    }

    private func restoreSnapshot(for services: [String]) async -> Bool {
        // Absence of a baseline authorizes no mutation.
        guard UserDefaults.standard.data(forKey: snapshotKey) != nil else { return true }
        guard let snapshots = loadSnapshot(), Set(snapshots.keys).isSubset(of: Set(services)) else { return false }
        guard let before = await readSnapshots(for: Array(snapshots.keys)) else { return false }
        let sudo = await PrivilegeService.shared.checkPrivileges()
        let outcome = await ProxyTransaction.apply(
            write: { await self.writeSnapshots(snapshots, useSudo: sudo) },
            verify: { await self.matches(snapshots) },
            rollback: { await self.writeSnapshots(before, useSudo: sudo) },
            verifyRollback: { await self.matches(before) })
        guard outcome == .committed else { return false }
        UserDefaults.standard.removeObject(forKey: snapshotKey)
        return true
    }

    private func readSnapshotSync(for service: String) -> ProxySnapshot? {
        func read(_ kind: String) -> (Bool, String, String)? {
            guard let output = runNetworksetup([kind, service]) else { return nil }
            var fields: [String: String] = [:]
            for line in output.components(separatedBy: .newlines) {
                let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                if parts.count == 2 { fields[String(parts[0])] = parts[1].trimmingCharacters(in: .whitespaces) }
            }
            guard let enabled = fields["Enabled"], ["Yes", "No"].contains(enabled),
                  let server = fields["Server"], let port = fields["Port"], Int(port) != nil else { return nil }
            return (enabled == "Yes", server, port)
        }
        guard let web = read("-getwebproxy"), let secure = read("-getsecurewebproxy"), let socks = read("-getsocksfirewallproxy"),
              let bypassOutput = runNetworksetup(["-getproxybypassdomains", service]) else { return nil }
        let bypass = bypassOutput.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("There aren't any bypass domains") }
        return ProxySnapshot(webEnabled: web.0, secureWebEnabled: secure.0, socksEnabled: socks.0,
            webServer: web.1, webPort: web.2, secureWebServer: secure.1, secureWebPort: secure.2,
            socksServer: socks.1, socksPort: socks.2, bypassDomains: bypass)
    }

    private func runNetworksetup(_ args: [String]) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else { return nil }
            return String(data: data, encoding: .utf8)
        } catch { return nil }
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

        commands.append(["-setproxybypassdomains", service] + (snapshot.bypassDomains.isEmpty ? ["Empty"] : snapshot.bypassDomains))

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
        guard !isUpdating else { return false }
        guard UserDefaults.standard.data(forKey: snapshotKey) != nil else { return true }
        return restoreSnapshotSync(for: getNetworkServicesSync())
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
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else { return [] }
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

        return []
    }

    private func targetServicesSync(from services: [String]) -> [String] {
        let priorityServices = ["Wi-Fi", "Ethernet", "USB 10/100/1000 LAN"]
        let activeServices = services.filter { service in
            priorityServices.contains { service.contains($0) }
        }
        return activeServices.isEmpty ? services : activeServices
    }

    private func restoreSnapshotSync(for services: [String]) -> Bool {
        guard let snapshots = loadSnapshot(), Set(snapshots.keys).isSubset(of: Set(services)) else { return false }
        for (service, snapshot) in snapshots {
            for args in restoreCommands(for: service, snapshot: snapshot) {
                guard runSudoNetworksetupSync(args) else { return false }
            }
            guard let actual = readSnapshotSync(for: service), equivalent(actual, snapshot) else { return false }
        }
        UserDefaults.standard.removeObject(forKey: snapshotKey)
        return true
    }
}
