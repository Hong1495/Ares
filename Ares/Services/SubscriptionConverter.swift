import Foundation

/// Service for converting subscription content to Clash YAML
class SubscriptionConverter {
    
    /// Convert Base64 encoded subscription content to Clash YAML
    /// Returns nil if conversion is not possible or not needed
    static func convert(content: String) -> String? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 1. If it looks like XML/HTML, it's probably an error page, ignore
        if trimmed.hasPrefix("<") { return nil }
        
        // 2. If it looks like YAML already, return nil (no conversion needed)
        // Check for common Clash top-level keys
        if trimmed.hasPrefix("proxies:") || trimmed.hasPrefix("port:") || trimmed.hasPrefix("mixed-port:") || trimmed.contains("\nproxies:") {
            return nil
        }
        
        // 3. Try Base64 Decoding
        // Some subs are plain text list of URIs, others are Base64 encoded list of URIs
        var decodedContent = trimmed
        if let decoded = decodeBase64(trimmed) {
            decodedContent = decoded
        }
        
        // 4. Parse URI List (vmess://, vless://, trojan://, ss://)
        if isURIList(decodedContent) {
            return parseURIList(decodedContent)
        }
        
        return nil
    }
    
    // MARK: - Helper Methods
    
    static func decodeBase64(_ string: String) -> String? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
        
        // Add padding
        let length = base64.count
        let paddingString = String(repeating: "=", count: (4 - length % 4) % 4)
        base64 += paddingString
        
        guard let data = Data(base64Encoded: base64) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    private static func isURIList(_ content: String) -> Bool {
        return content.contains("vmess://") ||
               content.contains("vless://") ||
               content.contains("trojan://") ||
               content.contains("ss://")
    }
    
    private static func parseURIList(_ content: String) -> String {
        var proxies: [[String: Any]] = []
        let lines = content.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            
            if let proxy = parseURI(trimmed) {
                proxies.append(proxy)
            }
        }
        
        if proxies.isEmpty { return "" }
        
        return generateYAML(proxies: proxies)
    }
    
    // MARK: - URI Parsers
    
    private static func parseURI(_ line: String) -> [String: Any]? {
        if line.hasPrefix("vmess://") {
            return parseVmess(line)
        } else if line.hasPrefix("vless://") {
            return parseVless(line)
        } else if line.hasPrefix("trojan://") {
            return parseTrojan(line)
        } else if line.hasPrefix("ss://") {
            return parseShadowsocks(line)
        }
        return nil
    }
    
    private static func parseVmess(_ uri: String) -> [String: Any]? {
        let base64Part = uri.replacingOccurrences(of: "vmess://", with: "")
        guard let decoded = decodeBase64(base64Part),
              let data = decoded.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        
        /*
         VMess JSON format:
         {
           "v": "2",
           "ps": "Name",
           "add": "server.com",
           "port": "443",
           "id": "uuid",
           "aid": "0",
           "scy": "auto",
           "net": "ws",
           "type": "none",
           "host": "host",
           "path": "/",
           "tls": "tls",
           "sni": "sni"
         }
         */
        
        var proxy: [String: Any] = [
            "name": json["ps"] as? String ?? "VMess Info",
            "type": "vmess",
            "server": json["add"] as? String ?? "",
            "port": Int(json["port"] as? String ?? "0") ?? 0,
            "uuid": json["id"] as? String ?? "",
            "alterId": Int(json["aid"] as? String ?? "0") ?? 0,
            "cipher": json["scy"] as? String ?? "auto"
        ]
        
        // Transport settings
        let net = json["net"] as? String ?? "tcp"
        if net == "ws" {
            proxy["network"] = "ws"
            proxy["ws-path"] = json["path"] as? String
            
            if let host = json["host"] as? String, !host.isEmpty {
                 proxy["ws-headers"] = ["Host": host]
            }
        } else if net == "grpc" {
            proxy["network"] = "grpc"
            if let path = json["path"] as? String {
                proxy["grpc-service-name"] = path
            }
        }
        
        // TLS settings
        let tls = json["tls"] as? String ?? ""
        if tls == "tls" {
            proxy["tls"] = true
            if let sni = json["sni"] as? String, !sni.isEmpty {
                proxy["servername"] = sni
            } else if let host = json["host"] as? String, !host.isEmpty {
                // Determine SNI from host if SNI missing
                proxy["servername"] = host
            }
        }
        
        return proxy
    }
    
    private static func parseVless(_ uri: String) -> [String: Any]? {
        // vless://uuid@host:port?params#name
        guard let url = URL(string: uri),
              let host = url.host,
              let port = url.port,
              let user = url.user else { return nil }
        
        var proxy: [String: Any] = [
            "name": url.fragment?.removingPercentEncoding ?? "VLESS Info",
            "type": "vless",
            "server": host,
            "port": port,
            "uuid": user
        ]
        
        // Parse components
        if let components = URLComponents(string: uri), let queryItems = components.queryItems {
            for item in queryItems {
                guard let value = item.value else { continue }
                switch item.name {
                case "security":
                    if value == "tls" {
                        proxy["tls"] = true
                    } else if value == "reality" {
                        proxy["tls"] = true
                        proxy["flow"] = "xtls-rprx-vision" // Reality usually implies vision or similar
                        proxy["reality-opts"] = ["public-key": "TODO", "short-id": "TODO"] // Verify handling later
                    }
                case "sni":
                    proxy["servername"] = value
                case "fp":
                    proxy["client-fingerprint"] = value
                case "pbk":
                    // Reality public key
                    // This creates complexity, basic VLESS for now
                    break
                case "type":
                    if value == "ws" {
                        proxy["network"] = "ws"
                    } else if value == "grpc" {
                        proxy["network"] = "grpc"
                    }
                case "path":
                    if proxy["network"] as? String == "ws" {
                        proxy["ws-path"] = value
                    } else if proxy["network"] as? String == "grpc" {
                        proxy["grpc-service-name"] = value
                    }
                case "host":
                     if proxy["network"] as? String == "ws" {
                         proxy["ws-headers"] = ["Host": value]
                     }
                default: break
                }
            }
        }
        
        return proxy
    }
    
    private static func parseTrojan(_ uri: String) -> [String: Any]? {
        // trojan://password@host:port?params#name
        guard let url = URL(string: uri),
              let host = url.host,
              let port = url.port,
              let user = url.user else { return nil }
        
        var proxy: [String: Any] = [
            "name": url.fragment?.removingPercentEncoding ?? "Trojan Info",
            "type": "trojan",
            "server": host,
            "port": port,
            "password": user
        ]
        
        if let components = URLComponents(string: uri), let queryItems = components.queryItems {
            for item in queryItems {
                guard let value = item.value else { continue }
                switch item.name {
                case "sni":
                    proxy["sni"] = value
                case "allowInsecure":
                    proxy["skip-cert-verify"] = (value == "1")
                case "type":
                    if value == "ws" {
                        proxy["network"] = "ws"
                    } else if value == "grpc" {
                        proxy["network"] = "grpc"
                    }
                case "path":
                    if proxy["network"] as? String == "ws" {
                        proxy["ws-path"] = value
                    } else if proxy["network"] as? String == "grpc" {
                        proxy["grpc-service-name"] = value
                    }
                case "host":
                    if proxy["network"] as? String == "ws" {
                        proxy["ws-headers"] = ["Host": value]
                    }
                default: break
                }
            }
        }
        
        return proxy
    }
    
    private static func parseShadowsocks(_ uri: String) -> [String: Any]? {
        // ss://method:password@host:port#name
        // or
        // ss://base64(method:password)@host:port#name
        
        // Very basic implementation. SS parsing can be complex due to legacy variants.
        // Assuming modern standard or SIP002
        
        guard let url = URL(string: uri) else { return nil }
        var name = url.fragment?.removingPercentEncoding ?? "SS Info"
        
        var method = ""
        var password = ""
        var host = ""
        var port = 0
        
        if let user = url.user {
            // Check if user is base64 encoded (legacy)
            // format: method:password
            if let decodedUser = decodeBase64(user) {
               let parts = decodedUser.split(separator: ":")
               if parts.count >= 2 {
                   method = String(parts[0])
                   password = String(parts[1])
               }
            } else {
                // Plain method:password (rare in URL but possible)
                // usually passed as user:password
                // URL parsing puts 'password' in url.password
                if let pass = url.password {
                    method = user
                    password = pass
                }
            }
            
            host = url.host ?? ""
            port = url.port ?? 0
        } else {
            // Check host part, might be Base64 encoded 'method:password@host:port'
             let stripped = uri.replacingOccurrences(of: "ss://", with: "").components(separatedBy: "#")[0]
             if let decoded = decodeBase64(stripped) {
                 // method:password@host:port
                 let atSplit = decoded.components(separatedBy: "@")
                 if atSplit.count == 2 {
                     let userInfo = atSplit[0].split(separator: ":")
                     if userInfo.count >= 2 {
                         method = String(userInfo[0])
                         password = String(userInfo[1])
                     }
                     
                     let serverInfo = atSplit[1].split(separator: ":")
                     if serverInfo.count == 2 {
                         host = String(serverInfo[0])
                         port = Int(serverInfo[1]) ?? 0
                     }
                 }
             }
        }
        
        if host.isEmpty || port == 0 { return nil }
        
        return [
            "name": name,
            "type": "ss",
            "server": host,
            "port": port,
            "cipher": method,
            "password": password
        ]
    }
    
    // MARK: - YAML Generator
    
    private static func generateYAML(proxies: [[String: Any]]) -> String {
        var yaml = "proxies:\n"
        var proxyNames: [String] = []
        
        for proxy in proxies {
            guard let name = proxy["name"] as? String else { continue }
            proxyNames.append(name)
            
            // Generate Proxy Block
            yaml += "  - name: \"\(name)\"\n"
            if let type = proxy["type"] as? String { yaml += "    type: \(type)\n" }
            if let server = proxy["server"] as? String { yaml += "    server: \(server)\n" }
            if let port = proxy["port"] as? Int { yaml += "    port: \(port)\n" }
            if let uuid = proxy["uuid"] as? String { yaml += "    uuid: \(uuid)\n" }
            if let alterId = proxy["alterId"] as? Int { yaml += "    alterId: \(alterId)\n" }
            if let cipher = proxy["cipher"] as? String { yaml += "    cipher: \(cipher)\n" }
            if let password = proxy["password"] as? String { yaml += "    password: \(password)\n" }
            if let tls = proxy["tls"] as? Bool, tls { yaml += "    tls: true\n" }
            if let sni = proxy["sni"] as? String { yaml += "    sni: \(sni)\n" }
            if let servername = proxy["servername"] as? String { yaml += "    servername: \(servername)\n" }
             if let skipCertVerify = proxy["skip-cert-verify"] as? Bool { yaml += "    skip-cert-verify: \(skipCertVerify)\n" }
            if let fingerprint = proxy["client-fingerprint"] as? String { yaml += "    client-fingerprint: \(fingerprint)\n" }
            
            // Network & Transport
            if let network = proxy["network"] { yaml += "    network: \(network)\n" }
            
            // WS Options (Consolidated)
            let wsPath = proxy["ws-path"] as? String
            let wsHeaders = proxy["ws-headers"] as? [String: String]
            
            if wsPath != nil || (wsHeaders != nil && !wsHeaders!.isEmpty) {
                yaml += "    ws-opts:\n"
                if let path = wsPath {
                    yaml += "      path: \(path)\n"
                }
                if let headers = wsHeaders, !headers.isEmpty {
                    yaml += "      headers:\n"
                    for (k, v) in headers {
                        yaml += "        \(k): \(v)\n"
                    }
                }
            }
            
            // Grpc Options
            if let serviceName = proxy["grpc-service-name"] {
                yaml += "    grpc-opts:\n"
                yaml += "      grpc-service-name: \(serviceName)\n"
            }
        }
        
        // Generate Proxy Groups
        yaml += "\nproxy-groups:\n"
        
        // 1. Auto Select
        yaml += "  - name: 🚀 Auto Select\n"
        yaml += "    type: url-test\n"
        yaml += "    url: http://www.gstatic.com/generate_204\n"
        yaml += "    interval: 300\n"
        yaml += "    proxies:\n"
        for name in proxyNames {
            yaml += "      - \"\(name)\"\n"
        }
        
        // 2. Fallback
        yaml += "  - name: 🐟 Fallback\n"
        yaml += "    type: fallback\n"
        yaml += "    url: http://www.gstatic.com/generate_204\n"
        yaml += "    interval: 300\n"
        yaml += "    proxies:\n"
        for name in proxyNames {
            yaml += "      - \"\(name)\"\n"
        }
        
        // 3. Main Proxy Selector
        yaml += "  - name: 🔰 Proxy\n"
        yaml += "    type: select\n"
        yaml += "    proxies:\n"
        yaml += "      - 🚀 Auto Select\n"
        yaml += "      - 🐟 Fallback\n"
        for name in proxyNames {
            yaml += "      - \"\(name)\"\n"
        }
        
        return yaml
    }
}
