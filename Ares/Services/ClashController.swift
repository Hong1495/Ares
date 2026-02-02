import Foundation
import Combine

/// Traffic statistics
struct TrafficStats: Codable {
    var up: Int64 = 0
    var down: Int64 = 0
}

/// Clash Rule
struct ClashRule: Codable, Identifiable {
    let id: UUID
    let type: String
    let payload: String
    let proxy: String
    let hit: Int
}

/// Represents a topological connection chain
struct ConnectionChain: Identifiable, Equatable {
    let id: String
    let host: String
    let sourceProcess: String
    let rule: String
    let chains: [String] // e.g. ["Rule", "HK Node", "Final"]
    let destinationIP: String
    let download: Int64
    let upload: Int64

    static func == (lhs: ConnectionChain, rhs: ConnectionChain) -> Bool {
        lhs.id == rhs.id && lhs.download == rhs.download && lhs.upload == rhs.upload
    }
}

/// Controller for interacting with Clash API
@MainActor
class ClashController: ObservableObject {
    static let shared = ClashController()

    // Dynamic base URL based on actual running mode
    private var currentPort: Int = 9097  // Default to Normal mode
    var baseURL: String {
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

    @Published var rules: [ClashRule] = []

    // Topology Data
    @Published var activeChains: [ConnectionChain] = []

    /// Current primary latency for display
    var primaryLatency: Int? {
        let allGroups = proxyGroups
        var activeGroupName: String? = nil

        if AppState.shared.currentMode == .global {
            activeGroupName = "GLOBAL"
        } else {
            if allGroups.contains(where: { $0.name == "🚀 节点选择" }) { activeGroupName = "🚀 节点选择" }
            else if allGroups.contains(where: { $0.name == "Proxy" }) { activeGroupName = "Proxy" }
            else if let fallback = allGroups.first(where: { $0.type == "Selector" && $0.name != "GLOBAL" }) { activeGroupName = fallback.name }
        }

        guard let gName = activeGroupName,
              let group = allGroups.first(where: { $0.name == gName }),
              let finalNode = group.resolveCurrentPath(groups: allGroups).last else {
            return nil
        }

        return proxyNodes[finalNode]?.delay
    }

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
            .combineLatest(ClashViewModel.shared.$isToggling)
            .receive(on: RunLoop.main)
            .sink { [weak self] isRunning, isToggling in
                if isRunning && !isToggling {
                    self?.consecutiveFailures = 0
                    // Add a tiny cool-down to ensure TCP ports are fully open by the kernel
                    Task {
                        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                        if let self = self, ClashViewModel.shared.isRunning, !ClashViewModel.shared.isToggling {
                            ClashViewModel.shared.addLog("[ClashController] 🟢 Core stable, activating monitors...")
                            self.startMonitors()
                        }
                    }
                } else {
                    if isToggling {
                        ClashViewModel.shared.addLog("[ClashController] 🟡 Toggling in progress, silencing monitors...")
                    }
                    self?.stopMonitors()
                }
            }
    }

    deinit {
        refreshTimer?.invalidate()
    }

    /// Start all monitors
    private func startMonitors() {
        // Trigger initial full sync IMMEDIATELY with retries
        Task { @MainActor in
            ClashViewModel.shared.addLog("[ClashController] 🔄 Initial state sync...")
            for i in 1...10 { // 10s window
                do {
                    try await self.fetchProxiesData()
                    try await self.fetchRules()
                    if let mode = try? await self.getCurrentMode() {
                        AppState.shared.currentMode = mode
                    }
                    ClashViewModel.shared.addLog("[ClashController] ✅ Initial sync completed (Attempt \(i))")
                    return
                } catch {
                    if i < 10 {
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                    }
                }
            }
        }

        // Start WebSocket for real-time traffic
        startTrafficMonitor()

        // Start polling for proxies - REMOVED: Managed by AppState heartbeat
/*
        stopRefreshTimer() // Safety clear
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                try? await self?.fetchProxiesData()
            }
        }
*/
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

    /// Dynamic Readiness Check: Polls the Clash API until it responds or timeouts.
    /// This is more elegant than a fixed Task.sleep().
    func waitForAPIReady(timeout: TimeInterval = 5.0) async -> Bool {
        let start = Date()
        let url = URL(string: "\(baseURL)/version")!

        while Date().timeIntervalSince(start) < timeout {
            do {
                let (_, response) = try await URLSession.shared.data(from: url)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    return true
                }
            } catch {
                // Ignore errors during retry period
            }
            // Wait briefly before retrying
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
        }
        return false
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
        trafficWebSocket?.cancel(with: .goingAway, reason: "Monitoring stopped".data(using: .utf8))
        trafficWebSocket = nil
        // Reset traffic stats to 0 when stopped
        DispatchQueue.main.async {
            self.traffic = TrafficStats()
        }
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

    private var lastTrafficUpdate: Date = Date()
    private var lastTrafficStats: TrafficStats = TrafficStats()

    private func receiveTrafficMessage() {
        guard isMonitoring, let ws = trafficWebSocket else { return }

        // 使用 async/await 循环而非递归，避免栈增长
        Task { @MainActor [weak self] in
            guard let self = self else { return }

            while self.isMonitoring, let currentWS = self.trafficWebSocket, currentWS === ws {
                do {
                    let message = try await currentWS.receive()

                    // 在后台解析
                    let stats = await Task.detached { [weak self] in
                        self?.parseTrafficMessage(message)
                    }.value

                    // 验证仍在监控且使用同一个 socket
                    guard self.isMonitoring, self.trafficWebSocket === ws else { break }

                    self.consecutiveFailures = 0
                    // 优化：在此处进行节流 (Throttling)
                    // 仅当距离上次更新超过 500ms 时才推送给 UI
                    let now = Date()
                    if let s = stats {
                        // 总是保存最新的 stats
                        self.lastTrafficStats = s

                        if now.timeIntervalSince(self.lastTrafficUpdate) > 0.5 {
                            self.traffic = s
                            self.lastTrafficUpdate = now
                        }
                    }

                } catch {
                    guard self.isMonitoring, self.trafficWebSocket === ws else { break }
                    self.consecutiveFailures += 1

                    let nsError = error as NSError
                    if nsError.code != 57 && nsError.code != -999 {
                        ClashViewModel.shared.addLog("[ClashController] ⚠️ Traffic WebSocket error (\(self.consecutiveFailures)/\(self.MAX_RETRY_FAILURES)): \(error.localizedDescription)")
                    }

                    if self.consecutiveFailures >= self.MAX_RETRY_FAILURES {
                        ClashViewModel.shared.addLog("[ClashController] 🛑 Max retry failures reached, stopping monitor")
                        self.stopTrafficMonitor()
                        break
                    }

                    try? await Task.sleep(nanoseconds: 1_000_000_000) // 1.0s wait
                    if self.isMonitoring && ClashViewModel.shared.isRunning {
                        self.restartMonitor()
                    }
                    break // 错误后退出循环，由 restartMonitor 重新开始
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

        // Parse in background to avoid blocking Main Actor
        let (groups, nodes) = await Task.detached(priority: .userInitiated) {
            guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let proxiesDict = json["proxies"] as? [String: [String: Any]] else {
                return ([], [:]) as ([ProxyGroup], [String: ProxyNode])
            }

            var groups: [ProxyGroup] = []
            var nodes: [String: ProxyNode] = [:]

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

                    // Parse ALL proxy groups
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
            return (groups, nodes)
        }.value

        // Update UI state
        self.proxyGroups = groups
        self.proxyNodes = nodes
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

            guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let delay = json["delay"] as? Int else {
                throw NSError(domain: "ClashController", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid delay response"])
            }

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

    /// Set Clash log level
    func setLogLevel(_ level: String) async throws {
        guard let url = URL(string: "\(baseURL)/configs") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["log-level": level]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, _) = try await URLSession.shared.data(for: request)
        ClashViewModel.shared.addLog("[ClashController] Set log level to \(level)")
    }

    /// Monitor active connections and update topology data
    func monitorConnections() async {
        do {
            guard let url = URL(string: "\(baseURL)/connections") else { return }
            let (data, _) = try await URLSession.shared.data(from: url)

            guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let connections = json["connections"] as? [[String: Any]] else {
                return
            }

            var newChains: [ConnectionChain] = []

            for conn in connections {
                guard let id = conn["id"] as? String,
                      let metadata = conn["metadata"] as? [String: Any],
                      let chains = conn["chains"] as? [String],
                      let rule = conn["rule"] as? String,
                      let upload = conn["upload"] as? Int64,
                      let download = conn["download"] as? Int64 else {
                    continue
                }

                let processPath = metadata["processPath"] as? String ?? metadata["process"] as? String ?? "Unknown"
                let destinationIP = metadata["destinationIP"] as? String ?? "0.0.0.0"

                // HOSTNAME FIX:
                // Direct IP connections might have empty host. Fallback to IP.
                let rawHost = metadata["host"] as? String ?? ""
                let host = rawHost.isEmpty ? destinationIP : rawHost

                // DATA CONSISTENCY FIX:
                // Apply the same "Standard Merging" logic as TrafficAuditManager.
                // 1. If it's inside an .app, use the App Name.
                // 2. Otherwise keep original filename.
                var finalProcessName = processPath.components(separatedBy: "/").last ?? processPath

                if processPath.contains(".app") {
                    let components = processPath.split(separator: "/")
                    var currentPath = ""
                    for component in components {
                        currentPath += "/" + component
                        if component.hasSuffix(".app") {
                            // Found the App Bundle -> Use App Name
                            finalProcessName = URL(fileURLWithPath: currentPath).deletingPathExtension().lastPathComponent
                            break
                        }
                    }
                }

                // Filter out self-traffic from "Ares" (Robust check)
                if finalProcessName.localizedCaseInsensitiveContains("Ares") || finalProcessName.localizedCaseInsensitiveContains("com.herastudio.ares") {
                    continue
                }

                let chain = ConnectionChain(
                    id: id,
                    host: host,
                    sourceProcess: finalProcessName,
                    rule: rule,
                    chains: chains,
                    destinationIP: destinationIP,
                    download: download,
                    upload: upload
                )
                newChains.append(chain)
            }

            // Only update if changed to avoid UI flickering
            if self.activeChains != newChains {
                self.activeChains = newChains
            }

        } catch {
            ClashViewModel.shared.addLog("[ClashController] ⚠️ Failed to get connections: \(error)")
        }
    }
    /// Fetch active rules from Clash API
    func fetchRules() async throws {
        guard let url = URL(string: "\(baseURL)/rules") else { return }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return
        }

        // Parse rules in background
        let rules = await Task.detached(priority: .utility) {
            guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let rulesList = json["rules"] as? [[String: Any]] else {
                return [] as [ClashRule]
            }

            var fetchedRules: [ClashRule] = []
            for ruleData in rulesList {
                if let type = ruleData["type"] as? String,
                   let payload = ruleData["payload"] as? String,
                   let proxy = ruleData["proxy"] as? String {
                    let hit = ruleData["hit"] as? Int ?? 0
                    fetchedRules.append(ClashRule(id: UUID(), type: type, payload: payload, proxy: proxy, hit: hit))
                }
            }
            return fetchedRules
        }.value

        self.rules = rules
    }
}
