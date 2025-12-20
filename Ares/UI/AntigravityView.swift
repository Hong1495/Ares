import SwiftUI
import Charts
import Combine

/// Specialized Dashboard for Google Antigravity Stats
struct AntigravityView: View {
    @ObservedObject private var trafficAnalyzer = TrafficAnalyzer.shared
    @ObservedObject private var clashController = ClashController.shared
    
    // Lifetime Stats
    @AppStorage("totalAntigravityTokens") private var tokenUsage: Int = 0
    
    
    @State private var googleLatency: Int = 0
    @State private var isOnline: Bool = false
    static var lastKnownLatency: Int = 0
    
    // Animation states
    @State private var healthColorGlow: Bool = false
    @State private var isDiagnosticsExpanded: Bool = true
    
    let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                // 1. NEURAL DASHBOARD HEADER
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text("Neural Link")
                                .font(.footnote.bold())
                                .foregroundStyle(.secondary)
                            
                            Circle()
                                .fill(isOnline ? Color.green : Color.secondary.opacity(0.3))
                                .frame(width: 8, height: 8)
                        }
                        
                        Text(isOnline ? "Established" : "Offline")
                            .font(.title2.bold())
                            .foregroundStyle(isOnline ? .primary : .secondary)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        HStack(spacing: 12) {
                            Button(action: clearAllStats) {
                                Image(systemName: "trash")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Clear all statistics")
                            
                            Button {
                                Task {
                                    await testLatency()
                                    await trafficAnalyzer.poll()
                                }
                            } label: {
                                Image(systemName: "play.circle")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Run connectivity and traffic test")
                            
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("Connection health")
                                    .font(.footnote)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.secondary)
                                
                                Text("\(trafficAnalyzer.healthScore)%")
                                    .font(.title2.bold())
                                    .foregroundStyle(healthColor(trafficAnalyzer.healthScore))
                            }
                        }
                    }
                }
                .padding(.horizontal, 4)
                
                // 2. HERO METRICS (TOKEN UNIVERSE)
                VStack(spacing: 24) {
                    // Lifetime display
                    VStack(spacing: 8) {
                        Text("Lifetime intelligence")
                            .font(.footnote.bold())
                            .foregroundStyle(.secondary)
                        
                        Text(formatTokens(Int64(trafficAnalyzer.lifetimeTokens * 5)))
                            .font(.system(size: 52, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                        
                        Text("Tokens synchronized")
                            .font(.footnote)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    }
                    
                    Divider()
                        .padding(.horizontal, 40)
                    
                    // Session stats
                    HStack(spacing: 40) {
                        VStack(spacing: 4) {
                            Text("TPS")
                                .font(.footnote.bold())
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.1f", trafficAnalyzer.currentTPS))
                                .font(.headline)
                                .monospacedDigit()
                        }
                        
                        VStack(spacing: 4) {
                            Text("Today")
                                .font(.footnote.bold())
                                .foregroundStyle(.secondary)
                            Text(formatTokens(trafficAnalyzer.totalBytes))
                                .font(.headline)
                                .monospacedDigit()
                        }
                        
                        VStack(spacing: 4) {
                            Text("Latency")
                                .font(.footnote.bold())
                                .foregroundStyle(.secondary)
                            Text("\(isOnline ? googleLatency : 0)ms")
                                .font(.headline)
                                .monospacedDigit()
                                .foregroundStyle(latencyColor(googleLatency))
                        }
                    }
                }
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)
                
                // 3. PROCESS SPLIT & NETWORK ACTIVITY
                HStack(alignment: .top, spacing: 16) {
                    // Core decomposition card
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Core decomposition")
                            .font(.headline)
                        
                        Spacer(minLength: 0)
                        
                        VStack(spacing: 16) {
                            ForEach(["Antigravity", "Language Server"], id: \.self) { key in
                                ProcessRow(name: key, 
                                           value: trafficAnalyzer.processSplit[key, default: 0], 
                                           total: trafficAnalyzer.processSplit.values.reduce(0, +))
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(12)
                    
                    // Link activity card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Link activity")
                                .font(.headline)
                            Spacer()
                            HStack(spacing: 12) {
                                HStack(spacing: 4) {
                                    Text("↓")
                                    Text(formatSpeed(trafficAnalyzer.currentAISpeedDown))
                                }
                                .foregroundStyle(.blue)
                                
                                HStack(spacing: 4) {
                                    Text("↑")
                                    Text(formatSpeed(trafficAnalyzer.currentAISpeedUp))
                                }
                                .foregroundStyle(.orange)
                            }
                            .font(.system(size: 12, design: .monospaced))
                            .fontWeight(.semibold)
                        }
                        
                        Spacer(minLength: 0)
                        
                        Chart {
                            ForEach(trafficAnalyzer.speedHistory) { point in
                                // Download series
                                AreaMark(x: .value("T", point.time), y: .value("V", point.down))
                                    .foregroundStyle(LinearGradient(colors: [.blue.opacity(0.15), .clear], startPoint: .top, endPoint: .bottom))
                                    .interpolationMethod(.catmullRom)
                                LineMark(x: .value("T", point.time), y: .value("V", point.down))
                                    .foregroundStyle(.blue)
                                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                                    .interpolationMethod(.catmullRom)
                                
                                // Upload series
                                AreaMark(x: .value("T", point.time), y: .value("V", point.up))
                                    .foregroundStyle(LinearGradient(colors: [.orange.opacity(0.15), .clear], startPoint: .top, endPoint: .bottom))
                                    .interpolationMethod(.catmullRom)
                                LineMark(x: .value("T", point.time), y: .value("V", point.up))
                                    .foregroundStyle(.orange)
                                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                                    .interpolationMethod(.catmullRom)
                            }
                        }
                        .chartXAxis(.hidden)
                        .chartYAxis(.hidden)
                        .frame(height: 52) 
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(12)
                }
                .frame(height: 160) // Fixed height for both to ensure perfect alignment
                
                // 4. LIVE REQUESTS STREAM (Flicker dots)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Live traffic stream")
                        .font(.headline)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(trafficAnalyzer.debugLogs.prefix(20), id: \.0) { log in
                                Circle()
                                    .fill(log.2 == "None" ? Color.red.opacity(0.5) : Color.blue)
                                    .frame(width: 4, height: 4)
                            }
                            if trafficAnalyzer.debugLogs.isEmpty {
                                Text("No activity")
                                    .font(.footnote)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)
                
                // 5. ADVANCED LINK DIAGNOSTICS
                DisclosureGroup(isExpanded: $isDiagnosticsExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Link diagnostics").font(.footnote.bold())
                            Spacer()
                            Button("Reset cache") { trafficAnalyzer.debugLogs.removeAll() }
                                .buttonStyle(.link)
                                .font(.footnote)
                                .fontWeight(.medium)
                        }
                        .foregroundStyle(.secondary)
                        
                        ForEach(trafficAnalyzer.debugLogs.prefix(10), id: \.0) { log in
                            HStack {
                                Text(log.0).font(.system(.footnote, design: .monospaced))
                                    .fontWeight(.medium)
                                    .lineLimit(1)
                                Spacer()
                                Text(formatTokens(log.3)).font(.system(.footnote, design: .monospaced))
                                    .fontWeight(.medium)
                                    .foregroundStyle(.secondary)
                                Text(log.1).font(.footnote)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.blue)
                                    .frame(width: 100, alignment: .trailing)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .padding(.top, 10)
                } label: {
                    Label("Technical diagnostics", systemImage: "chevron.right.square")
                        .font(.footnote)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(12)
            }
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onReceive(timer) { _ in
            withAnimation(.easeInOut(duration: 0.5)) {
                healthColorGlow.toggle()
            }
            Task {
                await trafficAnalyzer.poll()
                if Int.random(in: 0...4) == 0 { await testLatency() }
            }
        }
        .task {
            await Task.yield()
            await testLatency()
        }
    }
    
    // MARK: - Logic
    
    func clearAllStats() {
        trafficAnalyzer.resetStats()
        googleLatency = 0
    }
    
    func testLatency() async {
        let start = Date()
        var request = URLRequest(url: URL(string: "https://www.google.com/generate_204")!)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 2.0
        
        do {
            let (_, _) = try await URLSession.shared.data(for: request)
            let duration = Date().timeIntervalSince(start)
            let ms = Int(duration * 1000)
            
            await MainActor.run {
                DispatchQueue.main.async {
                    self.googleLatency = ms
                    self.isOnline = true
                    AntigravityView.lastKnownLatency = ms
                }
            }
        } catch {
            await MainActor.run {
                DispatchQueue.main.async {
                    self.googleLatency = -1
                    self.isOnline = false
                    AntigravityView.lastKnownLatency = -1
                }
            }
        }
    }
    
    func formatTokens(_ bytes: Int64) -> String {
        let tokens = Int(bytes) / 5
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: tokens)) ?? "\(tokens)"
    }
    
    func formatDetailedBytes(_ bytes: Int64) -> String {
        let b = Double(bytes)
        if b >= 1024 * 1024 * 1024 {
            return String(format: "%.2f GB", b / (1024 * 1024 * 1024))
        } else if b >= 1024 * 1024 {
            return String(format: "%.2f MB", b / (1024 * 1024))
        } else if b >= 1024 {
            return String(format: "%.1f KB", b / 1024)
        }
        return "\(bytes) B"
    }
    
    func formatSpeed(_ bytesPerSec: Int64) -> String {
            return formatDetailedBytes(bytesPerSec) + "/s"
    }

    func healthColor(_ score: Int) -> Color {
        if score > 80 { return .green }
        if score > 50 { return .orange }
        return .red
    }
    
    func latencyColor(_ ms: Int) -> Color {
        if ms < 0 { return .red }
        if ms < 150 { return .green }
        if ms < 300 { return .orange }
        return .red
    }
}

struct ProcessRow: View {
    let name: String
    let value: Int64
    let total: Int64
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(name)
                    .font(.footnote)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                Spacer()
                Text(formatDetailedBytes(value))
                    .font(.system(.footnote, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }
            
            GeometryReader { geo in
                let fraction = total > 0 ? CGFloat(Double(value) / Double(total)) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.1))
                    Capsule()
                        .fill(Color.blue)
                        .frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 4)
        }
    }
    
    func formatDetailedBytes(_ bytes: Int64) -> String {
        let b = Double(bytes)
        if b >= 1024 * 1024 { return String(format: "%.1fM", b / (1024 * 1024)) }
        if b >= 1024 { return String(format: "%.1fK", b / 1024) }
        return "\(bytes)B"
    }
}

// MARK: - Models & ViewModels

struct SpeedPoint: Identifiable {
    let id = UUID()
    let time: Date
    let down: Int64
    let up: Int64
}

// Persistent Data Model
struct DailyModelStats: Codable {
    var date: Date
    var stats: [String: Int64]
}

@MainActor
class TrafficAnalyzer: ObservableObject {
    static let shared = TrafficAnalyzer()
    
    @Published var modelStats: [TrafficItem] = []
    @Published var dailyStats: [DailyModelStats] = []
    @Published var lifetimeTokens: Int = 0
    @Published var speedHistory: [SpeedPoint] = []
    @Published var debugLogs: [(String, String, String, Int64)] = [] // (Host, Process, Match, TotalBytes)
    
    // Advanced Metrics
    @Published var currentTPS: Double = 0.0
    @Published var healthScore: Int = 100
    @Published var processSplit: [String: Int64] = ["Antigravity": 0, "Language Server": 0]
    
    private var connectionCache: [String: Int64] = [:]
    private var connectionCacheUp: [String: Int64] = [:]
    private var connectionCacheDown: [String: Int64] = [:]
    private var tpsHistory: [Double] = []
    @Published var currentAISpeedUp: Int64 = 0
    @Published var currentAISpeedDown: Int64 = 0
    
    struct TrafficItem: Identifiable {
        let id = UUID()
        let name: String
        var value: Int64
        var color: Color
    }
    
    private let storageKey = "antigravity_daily_stats"
    private let lifetimeKey = "totalAntigravityTokens"
    
    private init() {
        self.lifetimeTokens = UserDefaults.standard.integer(forKey: lifetimeKey)
        
        // Pre-fill speed history (focused on AI only)
        let now = Date()
        self.speedHistory = (0..<60).map { i in
            SpeedPoint(time: now.addingTimeInterval(Double(i - 60)), down: 0, up: 0)
        }
        
        loadStats()
    }
    
    var chartData: [TrafficItem] {
        let filtered = modelStats.filter { $0.value >= 1024 } // Filter noise < 1KB
        if filtered.isEmpty {
            return [TrafficItem(name: "Ready", value: 1, color: .gray.opacity(0.15))]
        }
        return filtered
    }
    
    var sortedStats: [TrafficItem] {
        modelStats.sorted { $0.value > $1.value }
    }
    
    var totalBytes: Int64 {
        modelStats.reduce(0) { $0 + $1.value }
    }

    func poll() async {
        guard let connections = try? await ClashController.shared.fetchConnections(),
              let list = connections["connections"] as? [[String: Any]] else {
            return
        }
        
        await processConnectionsBackground(list: list)
    }
    
    private func addToSpeedHistory(down: Int64, up: Int64) {
        let now = Date()
        currentAISpeedDown = down
        currentAISpeedUp = up
        
        speedHistory.append(SpeedPoint(time: now, down: down, up: up))
        if speedHistory.count > 60 {
            speedHistory.removeFirst()
        }
    }
    
    nonisolated private func processConnectionsBackground(list: [[String: Any]]) async {
        let result = await Task.detached(priority: .userInitiated) {
            var calculatedDeltas: [(String, Int64, Int64, String, String?)] = [] 
            
            for conn in list {
                 guard let id = conn["id"] as? String,
                       let download = conn["download"] as? Int64,
                       let upload = conn["upload"] as? Int64,
                       let metadata = conn["metadata"] as? [String: Any],
                       let host = metadata["host"] as? String else {
                     continue
                 }
                 let process = metadata["processPath"] as? String
                 calculatedDeltas.append((id, download, upload, host, process))
            }
            return calculatedDeltas
        }.value
        
        await MainActor.run {
            checkDayReset()
            var changes = false
            var currentActiveIDs = Set<String>()
            
            var totalAIUp: Int64 = 0
            var totalAIDown: Int64 = 0
            var totalDeltaInSession: Int64 = 0
            
            for (id, download, upload, host, process) in result {
                currentActiveIDs.insert(id)
                let previous = self.connectionCache[id] ?? 0
                let currentSum = download + upload
                let delta = currentSum >= previous ? (currentSum - previous) : currentSum
                
                if delta > 100 || host.contains("api.") || host.contains("anthropic") || host.contains("openai") || host.contains("google") {
                    if let category = self.identifyCategory(host: host, process: process) {
                        if delta > 0 {
                            totalAIUp += (upload > (self.connectionCacheUp[id] ?? 0)) ? (upload - (self.connectionCacheUp[id] ?? 0)) : 0
                            totalAIDown += (download > (self.connectionCacheDown[id] ?? 0)) ? (download - (self.connectionCacheDown[id] ?? 0)) : 0
                            totalDeltaInSession += delta
                            
                            let newTokens = Int(delta) / 5
                            if newTokens > 0 {
                                self.lifetimeTokens += newTokens
                                UserDefaults.standard.set(self.lifetimeTokens, forKey: self.lifetimeKey)
                            }
                            
                            if let index = self.modelStats.firstIndex(where: { $0.name == "Antigravity AI" }) {
                                self.modelStats[index].value += delta
                                changes = true
                            }
                            
                            // Process Split Tracking
                            let procKey = process?.lowercased().contains("language_server") == true ? "Language Server" : "Antigravity"
                            self.processSplit[procKey, default: 0] += delta
                        }
                        self.logMatch(host: host, process: process, match: category, bytes: delta)
                    } else {
                        if process?.lowercased().contains("antigravity") == true && delta > 0 {
                            self.logMatch(host: host, process: process, match: "None", bytes: delta)
                        }
                    }
                }
                
                self.connectionCache[id] = currentSum
                self.connectionCacheUp[id] = upload
                self.connectionCacheDown[id] = download
            }
            
            // Calculate TPS (Rolling average for smoothness)
            let instantTPS = Double(totalDeltaInSession) / 5.0
            self.tpsHistory.append(instantTPS)
            if self.tpsHistory.count > 3 { self.tpsHistory.removeFirst() }
            self.currentTPS = self.tpsHistory.reduce(0, +) / Double(self.tpsHistory.count)
            
            self.addToSpeedHistory(down: totalAIDown, up: totalAIUp)
            
            let cachedIDs = Set(self.connectionCache.keys)
            let closedIDs = cachedIDs.subtracting(currentActiveIDs)
            for id in closedIDs {
                self.connectionCache.removeValue(forKey: id)
                self.connectionCacheUp.removeValue(forKey: id)
                self.connectionCacheDown.removeValue(forKey: id)
            }
            
            if changes {
                self.saveStats()
            }
        }
    }
    
    func resetStats() {
        modelStats = [
            TrafficItem(name: "Antigravity AI", value: 0, color: .purple)
        ]
        lifetimeTokens = 0
        UserDefaults.standard.set(0, forKey: lifetimeKey)
        processSplit = ["Antigravity": 0, "Language Server": 0]
        currentTPS = 0
        healthScore = 100
        saveStats()
        // We do NOT clear connectionCache here, otherwise the next poll will 
        // treat current cumulative traffic as a massive new delta.
        speedHistory.removeAll() 
    }
    
    private func loadStats() {
        var tempStats: [TrafficItem] = [
            TrafficItem(name: "Antigravity AI", value: 0, color: .purple)
        ]
        
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode(DailyModelStats.self, from: data) {
            
            if Calendar.current.isDateInToday(saved.date) {
                for (name, val) in saved.stats {
                    if let idx = tempStats.firstIndex(where: { $0.name == name }) {
                        tempStats[idx].value = val
                    }
                }
            }
        }
        self.modelStats = tempStats
    }
    
    private func logMatch(host: String, process: String?, match: String, bytes: Int64) {
        let p = process?.components(separatedBy: "/").last ?? "Unknown"
        if let idx = debugLogs.firstIndex(where: { $0.0 == host && $0.2 == match }) {
            debugLogs[idx].3 += bytes
            let entry = debugLogs.remove(at: idx)
            debugLogs.insert(entry, at: 0)
        } else {
            let entry = (host, p, match, bytes)
            debugLogs.insert(entry, at: 0)
            if debugLogs.count > 15 {
                debugLogs.removeLast()
            }
        }
    }
    
    private func saveStats() {
        var dict: [String: Int64] = [:]
        for item in modelStats {
            dict[item.name] = item.value
        }
        let daily = DailyModelStats(date: Date(), stats: dict)
        if let data = try? JSONEncoder().encode(daily) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
    
    private func checkDayReset() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode(DailyModelStats.self, from: data) {
            if !Calendar.current.isDateInToday(saved.date) {
                Task { @MainActor in
                    resetStats()
                }
            }
        }
        
        // Update Health Score (Simulated trend based on latency)
        updateHealthScore()
    }
    
    private func updateHealthScore() {
        // Logic: Penalize score if speed is erratic or latency is high
        let latency = AntigravityView.lastKnownLatency
        var score = 100
        if latency > 200 { score -= 20 }
        if latency > 500 { score -= 40 }
        if latency < 0 { score = 0 } // Timeout
        
        // Dynamic recovery
        if self.healthScore < score {
            self.healthScore += 1
        } else if self.healthScore > score {
            self.healthScore -= 1
        }
    }
    
    private func identifyCategory(host: String, process: String?) -> String? {
        let h = host.lowercased()
        let p = process?.lowercased() ?? ""
        let isAntigravity = p.contains("antigravity") || p.contains("language_server")
        guard isAntigravity else { return nil }
        
        if h.contains("static") || h.contains("cdn") || h.contains("telemetry") || 
           h.contains("update") || h.contains("ads.") || h.contains("analytics") ||
           h.contains("gstatic") || h.contains("google-analytics") {
            return nil
        }
        return "Antigravity AI"
    }
}
