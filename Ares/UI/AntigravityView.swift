import SwiftUI
import Charts
import Combine

/// Specialized Dashboard for Google Antigravity Stats
struct AntigravityView: View {
    @ObservedObject private var trafficAnalyzer = TrafficAnalyzer.shared
    @ObservedObject private var clashController = ClashController.shared
    

    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {

                
                // 2. HERO METRICS (Tokens / Quotas)
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Label("Neural Link Quotas", systemImage: "bolt.ring.closed")
                            .font(.headline)
                        Spacer()
                        
                        if !trafficAnalyzer.quotaStatus.isEmpty {
                            Text("Real-time")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(4)
                        } else {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .scaleEffect(0.5)
                                    .frame(width: 12, height: 12)
                                Text("Scanning traffic...")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    
                    if !trafficAnalyzer.quotaStatus.isEmpty {
                        QuotaMonitorView(quotas: Array(trafficAnalyzer.quotaStatus.values).sorted { $0.provider < $1.provider })
                    } else {
                        // Empty State / Placeholder
                        VStack(spacing: 12) {
                            Image(systemName: "waveform.path.ecg")
                                .font(.system(size: 32))
                                .foregroundStyle(.secondary.opacity(0.3))
                            Text("Waiting for AI headers...")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Text("Trigger an AI action in Antigravity IDE to capture quotas.")
                                .font(.caption)
                                .foregroundStyle(.secondary.opacity(0.7))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)
                
                // Discovery Log (Debug Mode)
                if !trafficAnalyzer.discoveryLogs.isEmpty {
                    DiscoveryLogView(logs: trafficAnalyzer.discoveryLogs)
                }
                

            }
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Antigravity")

        .task {
            // Kick off initial poll if needed
            await trafficAnalyzer.poll()
        }
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
    @Published var debugLogs: [(String, String, String, Int64)] = []
    
    // Advanced Metrics
    @Published var currentTPS: Double = 0.0
    @Published var healthScore: Int = 100
    @Published var processSplit: [String: Int64] = ["Antigravity": 0, "Language Server": 0]
    
    @Published var currentAISpeedUp: Int64 = 0
    @Published var currentAISpeedDown: Int64 = 0
    
    // Quota & Discovery
    @Published var quotaStatus: [String: AIQuotaStatus] = [:]
    @Published var discoveryLogs: [String] = []
    
    struct TrafficItem: Identifiable, Equatable {
        let id = UUID()
        let name: String
        var value: Int64
        var color: Color
    }
    
    private let storageKey = "antigravity_daily_stats"
    private let lifetimeKey = "totalAntigravityTokens"
    
    private var processedRequestIds = Set<String>()
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        self.lifetimeTokens = UserDefaults.standard.integer(forKey: lifetimeKey)
        
        let now = Date()
        self.speedHistory = (0..<60).map { i in
            SpeedPoint(time: now.addingTimeInterval(Double(i - 60)), down: 0, up: 0)
        }
        
        loadStats()
        setupAnalysisSubscription()
        
        // Discovery Callback
        AIAnalysisService.shared.onDiscoveryLog = { [weak self] msg in
            self?.discoveryLogs.insert(msg, at: 0)
            if (self?.discoveryLogs.count ?? 0) > 50 {
                self?.discoveryLogs.removeLast()
            }
        }
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
        // No-op: We switched to Push based on BrowserAnalysisService
    }

    private func setupAnalysisSubscription() {
        // Subscribe to BrowserAnalysisService changes
        BrowserAnalysisService.shared.$lastReceived
            .throttle(for: .seconds(1), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] _ in
                self?.analyzeActiveTabs()
            }
            .store(in: &cancellables)
            
        // Maintenance timer
        Timer.publish(every: 5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateHealth()
            }
            .store(in: &cancellables)
    }
    
    private func analyzeActiveTabs() {
        let tabs = BrowserAnalysisService.shared.activeTabs
        var newTokens = 0
        var changes = false
        var activeDown: Int64 = 0
        var activeUp: Int64 = 0
        
        for tab in tabs {
            for req in tab.requests {
                // Determine traffic direction roughly from size fields if available
                // This is instantaneous estimation, imperfect but visual
                if req.status == .active || req.status == .pending {
                    // Simulate speed for active requests
                    activeUp += 1024 // 1KB generic churn
                }
                
                // Only analyze completed or failed requests that haven't been processed
                guard (req.status == .success || req.status == .error),
                      !processedRequestIds.contains(req.id) else {
                    continue
                }
                
                if let usage = AIAnalysisService.shared.analyze(request: req) {
                    processAIUsage(usage)
                    newTokens += usage.totalTokens
                    processedRequestIds.insert(req.id)
                    changes = true
                    
                    // Add momentary speed bump for chart visual
                    activeDown += Int64(usage.outputTokens * 4) // roughly bytes
                    activeUp += Int64(usage.inputTokens * 4)
                    activeDown += Int64(usage.outputTokens * 4) // roughly bytes
                    activeUp += Int64(usage.inputTokens * 4)
                }
                
                // Quota Analysis (separately, as it might appear on error responses too)
                if let quota = AIAnalysisService.shared.parseQuota(request: req) {
                    quotaStatus[quota.id] = quota
                    processedRequestIds.insert(req.id) // Ensure we mark it processed if we got useful data
                } 
                // Mark non-AI requests processed to avoid re-checking forever
                else if abs(req.timestamp.timeIntervalSinceNow) > 30 { 
                    processedRequestIds.insert(req.id) 
                }
            }
        }
        
        if changes {
            saveStats()
        }
        
        updateSpeedHistory(down: activeDown, up: activeUp)
    }
    
    private func processAIUsage(_ usage: AIModelUsage) {
        // Update Lifetime
        lifetimeTokens += usage.totalTokens
        UserDefaults.standard.set(lifetimeTokens, forKey: lifetimeKey)
        
        // Update Model Breakdown
        let modelName = usage.model
        if let index = modelStats.firstIndex(where: { $0.name == modelName }) {
            modelStats[index].value += Int64(usage.totalTokens)
        } else {
            modelStats.append(TrafficItem(name: modelName, value: Int64(usage.totalTokens), color: assignColor(for: modelName)))
        }
        
        // Update "Process Split" with Provider breakdown (e.g. Google, OpenAI)
        processSplit[usage.provider, default: 0] += Int64(usage.totalTokens)
        
        // Log for Debug
        let entry = (usage.provider, modelName, "\(usage.totalTokens) toks", Int64(usage.totalTokens))
        debugLogs.insert(entry, at: 0)
        if debugLogs.count > 20 { debugLogs.removeLast() }
        
        // Update TPS
        let tps = Double(usage.outputTokens) / (usage.latency > 0 ? usage.latency : 1.0)
        currentTPS = tps 
        
        // Update Health
        if usage.status >= 400 {
            healthScore = max(0, healthScore - 10)
        } else {
            healthScore = min(100, healthScore + 1)
        }
    }
    
    private func updateSpeedHistory(down: Int64, up: Int64) {
        let now = Date()
        currentAISpeedDown = down
        currentAISpeedUp = up
        
        speedHistory.append(SpeedPoint(time: now, down: down, up: up))
        if speedHistory.count > 60 {
            speedHistory.removeFirst()
        }
    }
    
    private func updateHealth() {
        healthScore = 100 // default
    }
    
    private func assignColor(for model: String) -> Color {
        let m = model.lowercased()
        if m.contains("gpt") { return .green }
        if m.contains("claude") { return .orange }
        if m.contains("gemini") || m.contains("palm") { return .blue }
        return .purple
    }
    
    func resetStats() {
        modelStats = []
        lifetimeTokens = 0
        UserDefaults.standard.set(0, forKey: lifetimeKey)
        currentTPS = 0
        healthScore = 100
        saveStats()
        speedHistory.removeAll() 
        processedRequestIds.removeAll()
    }
    
    private func loadStats() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode(DailyModelStats.self, from: data) {
            
            if Calendar.current.isDateInToday(saved.date) {
                var items: [TrafficItem] = []
                for (name, val) in saved.stats {
                    items.append(TrafficItem(name: name, value: val, color: assignColor(for: name)))
                }
                self.modelStats = items
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
}

