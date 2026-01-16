import Foundation
import SystemConfiguration

/// System proxy configuration manager
class SystemProxyManager {
    static let shared = SystemProxyManager()
    
    private init() {}
    
    /// Set system proxy using networksetup command with administrator privileges
    /// This will prompt for password on each toggle
    /// Set system proxy using networksetup command
    /// Uses password-less sudo if available, otherwise prompts for password
    func setSystemProxy(enabled: Bool, httpPort: Int = 7890, socksPort: Int = 7891, bypassRules: String = "") async -> Bool {
        print("[SystemProxy] \(enabled ? "Enabling" : "Disabling") system proxy via networksetup...")
        
        let bypassArray = bypassRules.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        
        // CRITICAL: Run ENTIRE operation on background thread (including getNetworkServicesSync)
        return await Task.detached {
            let services = await self.getNetworkServices()
            guard !services.isEmpty else {
                print("[SystemProxy] No network services found")
                return false
            }
            
            // --- 1. Try Direct Sudo (Password-less) ---
            if await PrivilegeService.shared.checkPrivileges() {
                print("[SystemProxy] ⚡️ Using password-less sudo...")
                
                // Smart Filtering: Only apply to active/relevant interfaces to avoid overhead
                let priorityServices = ["Wi-Fi", "Ethernet", "USB 10/100/1000 LAN"]
                let activeServices = services.filter { service in
                    priorityServices.contains { service.contains($0) }
                }
                
                let targetServices = activeServices.isEmpty ? services : activeServices
                
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
                
                print("[SystemProxy] ✅ System proxy updated (Sudoers)")
                return true
            }
        
            // --- 2. Fallback to AppleScript (Password Prompt) ---
            print("[SystemProxy] 🔐 Requesting administrator privileges...")
            
            var commands: [String] = []
            for service in services {
                if enabled {
                    // Enable proxies
                    commands.append("networksetup -setwebproxy '\(service)' 127.0.0.1 \(httpPort)")
                    commands.append("networksetup -setsecurewebproxy '\(service)' 127.0.0.1 \(httpPort)")
                    commands.append("networksetup -setsocksfirewallproxy '\(service)' 127.0.0.1 \(socksPort)")
                    commands.append("networksetup -setwebproxystate '\(service)' on")
                    commands.append("networksetup -setsecurewebproxystate '\(service)' on")
                    commands.append("networksetup -setsocksfirewallproxystate '\(service)' on")
                    
                    // Apply bypass rules
                    if !bypassArray.isEmpty {
                        let bypassStr = bypassArray.map { "'\($0)'" }.joined(separator: " ")
                        commands.append("networksetup -setproxybypassdomains '\(service)' \(bypassStr)")
                    }
                } else {
                    // Disable proxies
                    commands.append("networksetup -setwebproxystate '\(service)' off")
                    commands.append("networksetup -setsecurewebproxystate '\(service)' off")
                    commands.append("networksetup -setsocksfirewallproxystate '\(service)' off")
                }
            }
            
            let shellCommands = commands.joined(separator: " && ")
            let script = """
            do shell script "\(shellCommands)" with administrator privileges
            """
            
            guard let appleScript = NSAppleScript(source: script) else {
                print("[SystemProxy] Failed to create AppleScript")
                return false
            }
            
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            
            if let error = error {
                print("[SystemProxy] Error: \(error)")
                return false
            }
            
            print("[SystemProxy] ✅ System proxy \(enabled ? "enabled" : "disabled")")
            return true
        }.value
    }
    
    private static var cachedServices: [String] = []
    private static var lastCacheUpdate: Date = .distantPast
    
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
        } catch {
            print("[SystemProxy] Failed to get network services: \(error)")
        }
        
        return await MainActor.run { Self.cachedServices.isEmpty ? ["Wi-Fi", "Ethernet"] : Self.cachedServices }
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
    func disableAllProxiesSync() {
        print("[SystemProxy] 🛑 Synchronous cleanup - disabling all proxies...")
        
        let priorityServices = ["Wi-Fi", "Ethernet", "USB 10/100/1000 LAN"]
        
        for service in priorityServices {
            let commands: [[String]] = [
                ["-setwebproxystate", service, "off"],
                ["-setsecurewebproxystate", service, "off"],
                ["-setsocksfirewallproxystate", service, "off"]
            ]
            
            for args in commands {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
                task.arguments = ["-n", "/usr/sbin/networksetup"] + args
                task.standardOutput = FileHandle.nullDevice
                task.standardError = FileHandle.nullDevice
                
                try? task.run()
                task.waitUntilExit()
            }
        }
        
        print("[SystemProxy] ✅ All proxies disabled")
    }
}
