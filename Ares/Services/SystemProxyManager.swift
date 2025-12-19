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
    func setSystemProxy(enabled: Bool, httpPort: Int = 7890, socksPort: Int = 7891) async -> Bool {
        print("[SystemProxy] \(enabled ? "Enabling" : "Disabling") system proxy via networksetup...")
        
        // CRITICAL: Run ENTIRE operation on background thread (including getNetworkServices)
        return await Task.detached {
            let services = self.getNetworkServicesSync()
            guard !services.isEmpty else {
                print("[SystemProxy] No network services found")
                return false
            }
            
            // --- 1. Try Direct Sudo (Password-less) ---
            if await PrivilegeService.shared.checkPrivileges() {
                print("[SystemProxy] ⚡️ Using password-less sudo...")
                
                for service in services {
                    var commandsToRun: [[String]] = []
                    
                    if enabled {
                        commandsToRun.append(["-setwebproxy", service, "127.0.0.1", "\(httpPort)"])
                        commandsToRun.append(["-setsecurewebproxy", service, "127.0.0.1", "\(httpPort)"])
                        commandsToRun.append(["-setsocksfirewallproxy", service, "127.0.0.1", "\(socksPort)"])
                        commandsToRun.append(["-setwebproxystate", service, "on"])
                        commandsToRun.append(["-setsecurewebproxystate", service, "on"])
                        commandsToRun.append(["-setsocksfirewallproxystate", service, "on"])
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
                        task.waitUntilExit()  // OK to block - we're on background thread
                        
                        if task.terminationStatus != 0 {
                            print("[SystemProxy] ⚠️ Sudo command failed for \(service)")
                        }
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
    
    /// Get list of network services (Wi-Fi, Ethernet, etc.)
    nonisolated private func getNetworkServicesSync() -> [String] {
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
                // Parse output, skip first line (header)
                let lines = output.components(separatedBy: .newlines)
                    .dropFirst()
                    .filter { !$0.isEmpty && !$0.hasPrefix("*") }
                return Array(lines)
            }
        } catch {
            print("[SystemProxy] Failed to get network services: \(error)")
        }
        
        // Fallback to common service names
        return ["Wi-Fi", "Ethernet"]
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
}
