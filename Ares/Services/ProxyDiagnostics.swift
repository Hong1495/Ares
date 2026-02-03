import Foundation

/// Service for testing proxy connectivity
@MainActor
class ProxyDiagnostics {
    static let shared = ProxyDiagnostics()
    
    private init() {}
    
    /// Test if proxy is actually working
    func testProxyConnection() async {
        ClashViewModel.shared.addLog("[Diagnostics] 🔍 Starting proxy connection test...")
        
        // Test 1: Check if Clash API is accessible
        await testClashAPI()
        
        // Test 2: Test HTTP proxy
        await testHTTPProxy()
        
        // Test 3: Test SOCKS proxy
        await testSOCKSProxy()
        
        // Test 4: Test actual internet connection through proxy
        await testRealConnection()
        
        ClashViewModel.shared.addLog("[Diagnostics] ✅ Diagnostics complete")
    }
    
    private func testClashAPI() async {
        do {
            guard let url = URL(string: "http://127.0.0.1:\(ClashPorts.apiNormal)/version") else { return }
            let (data, response) = try await URLSession.shared.data(from: url)
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let version = json["version"] as? String {
                        ClashViewModel.shared.addLog("[Diagnostics] ✅ Clash API accessible (v\(version))")
                    }
                } else {
                    ClashViewModel.shared.addLog("[Diagnostics] ⚠️ Clash API HTTP \(httpResponse.statusCode)")
                }
            }
        } catch {
            ClashViewModel.shared.addLog("[Diagnostics] ❌ Clash API unreachable: \(error)")
        }
    }
    
    private func testHTTPProxy() async {
        ClashViewModel.shared.addLog("[Diagnostics] 🔌 Testing HTTP proxy on 127.0.0.1:\(ClashPorts.defaultMixed)...")
        
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable: true,
            kCFNetworkProxiesHTTPProxy: "127.0.0.1",
            kCFNetworkProxiesHTTPPort: ClashPorts.defaultMixed
        ]
        
        let session = URLSession(configuration: config)
        
        do {
            guard let url = URL(string: "http://www.gstatic.com/generate_204") else { return }
            let (_, response) = try await session.data(from: url)
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 204 {
                    ClashViewModel.shared.addLog("[Diagnostics] ✅ HTTP proxy working (204)")
                } else {
                    ClashViewModel.shared.addLog("[Diagnostics] ⚠️ HTTP proxy returned \(httpResponse.statusCode)")
                }
            }
        } catch {
            ClashViewModel.shared.addLog("[Diagnostics] ❌ HTTP proxy failed: \(error.localizedDescription)")
        }
    }
    
    private func testSOCKSProxy() async {
        ClashViewModel.shared.addLog("[Diagnostics] 🔌 Testing SOCKS proxy on 127.0.0.1:\(ClashPorts.defaultSocks)...")
        
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [
            kCFNetworkProxiesSOCKSEnable: true,
            kCFNetworkProxiesSOCKSProxy: "127.0.0.1",
            kCFNetworkProxiesSOCKSPort: ClashPorts.defaultSocks
        ]
        
        let session = URLSession(configuration: config)
        
        do {
            guard let url = URL(string: "http://www.gstatic.com/generate_204") else { return }
            let (_, response) = try await session.data(from: url)
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 204 {
                    ClashViewModel.shared.addLog("[Diagnostics] ✅ SOCKS proxy working (204)")
                } else {
                    ClashViewModel.shared.addLog("[Diagnostics] ⚠️ SOCKS proxy returned \(httpResponse.statusCode)")
                }
            }
        } catch {
            ClashViewModel.shared.addLog("[Diagnostics] ❌ SOCKS proxy failed: \(error.localizedDescription)")
        }
    }
    
    private func testRealConnection() async {
        ClashViewModel.shared.addLog("[Diagnostics] 🌐 Testing real connection to google.com...")
        
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable: true,
            kCFNetworkProxiesHTTPProxy: "127.0.0.1",
            kCFNetworkProxiesHTTPPort: ClashPorts.defaultMixed,
            kCFNetworkProxiesHTTPSEnable: true,
            kCFNetworkProxiesHTTPSProxy: "127.0.0.1",
            kCFNetworkProxiesHTTPSPort: ClashPorts.defaultMixed
        ]
        
        let session = URLSession(configuration: config)
        
        do {
            guard let url = URL(string: "https://www.google.com") else { return }
            let startTime = Date()
            let (_, response) = try await session.data(from: url)
            let duration = Date().timeIntervalSince(startTime)
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    ClashViewModel.shared.addLog("[Diagnostics] ✅ Google accessible (\(Int(duration * 1000))ms)")
                } else {
                    ClashViewModel.shared.addLog("[Diagnostics] ⚠️ Google returned \(httpResponse.statusCode)")
                }
            }
        } catch {
            ClashViewModel.shared.addLog("[Diagnostics] ❌ Google unreachable: \(error.localizedDescription)")
        }
    }
}
