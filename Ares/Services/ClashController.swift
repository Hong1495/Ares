import Foundation
import Combine

/// Traffic statistics
struct TrafficStats: Codable {
    var up: Int64 = 0
    var down: Int64 = 0
}

/// Controller for interacting with Clash API
@MainActor
class ClashController: ObservableObject {
    static let shared = ClashController()
    
    // Dynamic base URL based on actual running mode
    private var currentPort: Int = 9097  // Default to Normal mode
    private var baseURL: String {
        return "http://127.0.0.1:\(currentPort)"
    }
    
    /// Update the API port based on current TUN state
    func updatePort(tunEnabled: Bool) {
        currentPort = tunEnabled ? 19097 : 9097
    }
    
    @Published var traffic = TrafficStats()
    @Published var proxies: [String: Any] = [:]
    @Published var proxyGroups: [ProxyGroup] = []
    @Published var proxyNodes: [String: ProxyNode] = [:]
    
    private var statusSubscription: AnyCancellable?
    private var refreshTimer: Timer?
    
    // Retry limiting
    private var consecutiveFailures = 0
    private let MAX_RETRY_FAILURES = 5
    
    private init() {
        setupLifecycleObserver()
    }
    
    private func setupLifecycleObserver() {
        // Reactive Lifecycle: Only start monitoring when ClashService reports it is running
        statusSubscription = ClashViewModel.shared.$isRunning
            .receive(on: RunLoop.main)
            .sink { [weak self] isRunning in
                if isRunning {
                    ClashViewModel.shared.addLog("[ClashController] 🟢 Core running, activating monitors...")
                    self?.consecutiveFailures = 0  // Reset failure counter
                    self?.startMonitors()
                } else {
                     ClashViewModel.shared.addLog("[ClashController] 🔴 Core stopped, deactivating monitors...")
                    self?.stopMonitors()
                }
            }
    }
    
    deinit {
        refreshTimer?.invalidate()
    }
    
    /// Start all monitors
    private func startMonitors() {
        // Start WebSocket for real-time traffic
        startTrafficMonitor()
        
        // Start polling for proxies
        stopRefreshTimer() // Safety clear
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                try? await self?.fetchProxiesData()
            }
        }
        // Initial fetch
        Task { try? await fetchProxiesData() }
    }
    
    /// Stop all monitors
    private func stopMonitors() {
        stopTrafficMonitor()
        stopRefreshTimer()
    }
    
    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    private var trafficWebSocket: URLSessionWebSocketTask?
    private var isMonitoring = false
    
    /// Start monitoring traffic via WebSocket
    func startTrafficMonitor() {
        guard !isMonitoring else { return }
        
        stopTrafficMonitor()
        isMonitoring = true
        
        ClashViewModel.shared.addLog("[ClashController] 🟢 Starting traffic monitor (WebSocket)")
        
        let url = URL(string: "ws://127.0.0.1:\(currentPort)/traffic?token=")
        guard let wsUrl = url else { return }
        
        trafficWebSocket = URLSession.shared.webSocketTask(with: wsUrl)
        trafficWebSocket?.resume()
        
        receiveTrafficMessage()
    }
    
    func stopTrafficMonitor() {
        isMonitoring = false
        trafficWebSocket?.cancel(with: .goingAway, reason: nil)
        trafficWebSocket = nil
    }
    
    private func restartMonitor() {
        guard isMonitoring else { return }
        // Don't call stopTrafficMonitor() here as it sets isMonitoring=false
        trafficWebSocket?.cancel(with: .goingAway, reason: nil)
        trafficWebSocket = nil
        
        let url = URL(string: "ws://127.0.0.1:\(currentPort)/traffic?token=")
        guard let wsUrl = url else { return }
        
        trafficWebSocket = URLSession.shared.webSocketTask(with: wsUrl)
        trafficWebSocket?.resume()
        
        receiveTrafficMessage()
    }
    
    private func receiveTrafficMessage() {
        guard isMonitoring, let ws = trafficWebSocket else { return }
        
        ws.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                // Process in background first
                Task.detached {
                    let stats = self.parseTrafficMessage(message)
                    
                    await MainActor.run {
                        // Verify we are still monitoring and using the same socket
                        guard self.isMonitoring && self.trafficWebSocket === ws else { return }
                        
                        self.consecutiveFailures = 0
                        if let s = stats {
                            self.traffic = s
                        }
                        self.receiveTrafficMessage() // Recursively listen
                    }
                }
                
            case .failure(let error):
                Task { @MainActor in
                    guard self.isMonitoring && self.trafficWebSocket === ws else { return }
                    self.consecutiveFailures += 1
                    
                    let nsError = error as NSError
                    if nsError.code != 57 && nsError.code != -999 {
                        ClashViewModel.shared.addLog("[ClashController] ⚠️ Traffic WebSocket error (\(self.consecutiveFailures)/\(self.MAX_RETRY_FAILURES)): \(error.localizedDescription)")
                    }
                    
                    if self.consecutiveFailures >= self.MAX_RETRY_FAILURES {
                        ClashViewModel.shared.addLog("[ClashController] 🛑 Max retry failures reached, stopping monitor")
                        self.stopTrafficMonitor()
                        return
                    }
                    
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    if self.isMonitoring && ClashViewModel.shared.isRunning {
                        self.restartMonitor()
                    }
                }
            }
        }
    }
    
    // Pure parsing function (thread-safe)
    nonisolated private func parseTrafficMessage(_ message: URLSessionWebSocketTask.Message) -> TrafficStats? {
        let data: Data?
        switch message {
        case .data(let d): data = d
        case .string(let s): data = s.data(using: .utf8)
        @unknown default: data = nil
        }
        
        guard let data = data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let up = json["up"] as? Int64,
              let down = json["down"] as? Int64 else {
            return nil
        }
        
        return TrafficStats(up: up, down: down)
    }
    
    /// Deprecated: HTTP polling
    func fetchTraffic() async throws {
        // No-op
    }
    
    /// Fetch and parse proxies from Clash API
    func fetchProxiesData() async throws {
        // Removed noisy log: ClashService.shared.addLog("[ClashController] 📡 Fetching proxy data...")
        let url = URL(string: "\(baseURL)/proxies")!
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        
        guard let proxiesDict = json["proxies"] as? [String: [String: Any]] else {
            ClashViewModel.shared.addLog("[ClashController] ❌ No proxies found in response")
            return
        }
        
        var groups: [ProxyGroup] = []
        var nodes: [String: ProxyNode] = [:]
        
        // Parse ALL proxy groups and nodes
        for (name, proxyData) in proxiesDict {
            if let type = proxyData["type"] as? String {
                // Check if it's a node (has history or delay)
                if let history = proxyData["history"] as? [[String: Any]] {
                    let delay = history.first?["delay"] as? Int
                    let node = ProxyNode(
                        name: name,
                        type: type,
                        delay: delay
                    )
                    nodes[name] = node
                }
                
                // Parse ALL proxy groups (Selector, URLTest, Fallback, LoadBalance, Relay, etc.)
                // Don't filter - include everything that has 'all' array
                if let all = proxyData["all"] as? [String], !all.isEmpty {
                    let now = proxyData["now"] as? String
                    
                    let group = ProxyGroup(
                        name: name,
                        type: type,
                        now: now,
                        all: all
                    )
                    groups.append(group)
                }
            }
        }
        
        await MainActor.run {
            self.proxyGroups = groups
            self.proxyNodes = nodes
            // Only log on first fetch or significant changes
            // Removed: ClashService.shared.addLog("[ClashController] ✅ Loaded \(groups.count) groups, \(nodes.count) nodes")
        }
    }
    
    /// Select a proxy in a group
    func selectProxy(group: String, proxy: String) async throws {
        ClashViewModel.shared.addLog("[ClashController] 🎯 Selecting proxy: \(proxy) in group: \(group)")
        
        // URL encode the group name (contains Chinese/emoji)
        guard let encodedGroup = group.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(baseURL)/proxies/\(encodedGroup)") else {
            ClashViewModel.shared.addLog("[ClashController] ❌ Failed to encode group: \(group)")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["name": proxy]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 204 {
                ClashViewModel.shared.addLog("[ClashController] ✅ Proxy selected successfully")
            } else {
                ClashViewModel.shared.addLog("[ClashController] ⚠️ HTTP \(httpResponse.statusCode)")
            }
        }
    }
    
    /// Test proxy delay
    func testProxyDelay(name: String, timeout: Int = 5000) async throws -> Int {
        guard let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(baseURL)/proxies/\(encodedName)/delay?timeout=\(timeout)&url=http://www.gstatic.com/generate_204") else {
            ClashViewModel.shared.addLog("[ClashController] ❌ Invalid proxy name for test: \(name)")
            throw NSError(domain: "ClashController", code: -1)
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            if let httpResp = response as? HTTPURLResponse, httpResp.statusCode >= 400 {
                 ClashViewModel.shared.addLog("[ClashController] ⚠️ Test failed for \(name): HTTP \(httpResp.statusCode)")
                 throw NSError(domain: "ClashController", code: httpResp.statusCode)
            }
            
            let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            let delay = json["delay"] as! Int // Clash returns 'delay', some versions 'value'
            
            // ClashService.shared.addLog("[ClashController] ✅ \(name): \(delay)ms")
            
            // Update node delay in memory
            await MainActor.run {
                if var node = proxyNodes[name] {
                    node.delay = delay
                    proxyNodes[name] = node
                }
            }
            return delay
        } catch {
            ClashViewModel.shared.addLog("[ClashController] ❌ Test error for \(name): \(error.localizedDescription)")
            throw error
        }
        

    }
    
    /// Fetch proxies (legacy)
    func fetchProxies() async throws -> [String: Any] {
        try await fetchProxiesData()
        return proxies
    }
    
    /// Fetch connections from Clash API
    func fetchConnections() async throws -> [String: Any] {
        guard let url = URL(string: "\(baseURL)/connections") else {
            throw NSError(domain: "ClashController", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return json ?? [:]
    }
    
    /// Set Clash mode (rule/global/direct)
    func setMode(_ mode: ClashConfig.Mode) async throws {
        guard let url = URL(string: "\(baseURL)/configs") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["mode": mode.rawValue]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (_, _) = try await URLSession.shared.data(for: request)
        
        print("[ClashController] Set mode to \(mode.rawValue)")
    }
    
    /// Get current Clash mode
    func getCurrentMode() async throws -> ClashConfig.Mode {
        guard let url = URL(string: "\(baseURL)/configs") else {
            throw NSError(domain: "ClashController", code: 1, userInfo: nil)
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        if let modeString = json?["mode"] as? String,
           let mode = ClashConfig.Mode(rawValue: modeString) {
            return mode
        }
        
        throw NSError(domain: "ClashController", code: 2, userInfo: nil)
    }
    
    /// Monitor active connections
    func monitorConnections() async {
        do {
            guard let url = URL(string: "\(baseURL)/connections") else { return }
            let (data, _) = try await URLSession.shared.data(from: url)
            let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            
            if let connections = json["connections"] as? [[String: Any]] {
                let count = connections.count
                ClashViewModel.shared.addLog("[ClashController] 🔗 Active connections: \(count)")
                
                // Log recent connections
                for (index, conn) in connections.prefix(5).enumerated() {
                    if let metadata = conn["metadata"] as? [String: Any],
                       let host = metadata["host"] as? String,
                       let chains = conn["chains"] as? [String] {
                        let proxy = chains.first ?? "DIRECT"
                        ClashViewModel.shared.addLog("[ClashController]   \(index + 1). \(host) → \(proxy)")
                    }
                }
            }
        } catch {
            ClashViewModel.shared.addLog("[ClashController] ⚠️ Failed to get connections: \(error)")
        }
    }
}
