import SwiftUI

import Combine

/// Specialized Dashboard for Google Antigravity Stats
struct AntigravityView: View {
    @ObservedObject private var trafficAnalyzer = TrafficAnalyzer.shared
    @ObservedObject private var clashController = ClashController.shared
    

    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                // 1. AVAILABLE MODELS (From IDE)
                if !trafficAnalyzer.availableModels.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Label("Available Models", systemImage: "sparkles.rectangle.stack")
                                .font(.headline)
                            Spacer()
                            Text("\(trafficAnalyzer.availableModels.count) Models")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        ForEach(groupedModels, id: \.key) { provider, models in
                            Section {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12)], spacing: 12) {
                                    ForEach(models) { model in
                                        ModelCard(model: model)
                                    }
                                }
                            } header: {
                                HStack {
                                    Image(systemName: providerIcon(for: provider))
                                    Text(provider)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 8)
                            }
                        }
                    }
                    .padding(20)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(12)
                } else {
                    // Empty State / Placeholder
                    VStack(spacing: 12) {
                        Image(systemName: "server.rack")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary.opacity(0.3))
                        Text("Waiting for model list...")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text("Open the model picker in Antigravity to sync.")
                            .font(.caption)
                            .foregroundStyle(.secondary.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(12)
                }
                
                // Discovery Log removed per user request
                
            }
            .padding(20)
        } // End ScrollView
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Antigravity")

        .task {
            // Kick off initial poll if needed
            await trafficAnalyzer.poll()
        }
    }
    private var groupedModels: [(key: String, value: [AntigravityModelInfo])] {
        let filtered = trafficAnalyzer.availableModels.filter { model in
            let name = model.displayName
            return name.hasPrefix("Gemini") || name.hasPrefix("Claude") || name.hasPrefix("GPT")
        }
        
        let grouped = Dictionary(grouping: filtered) { model -> String in
            let name = model.displayName
            if name.hasPrefix("Gemini") { return "Google Gemini" }
            if name.hasPrefix("Claude") { return "Anthropic Claude" }
            if name.hasPrefix("GPT") { return "OpenAI GPT" }
            return "Other" // Should not happen given filter
        }
        
        // Sort keys: Google, then Claude, then OpenAI
        let sortedKeys = grouped.keys.sorted { k1, k2 in
            let order = ["Google Gemini": 0, "Anthropic Claude": 1, "OpenAI GPT": 2]
            return (order[k1] ?? 99) < (order[k2] ?? 99)
        }
        
        return sortedKeys.map { key in
            (key: key, value: grouped[key]?.sorted(by: sortModels) ?? [])
        }
    }
    
    private func sortModels(_ m1: AntigravityModelInfo, _ m2: AntigravityModelInfo) -> Bool {
        // High level sort: Recommended first
        // if (m1.recommended == true) != (m2.recommended == true) { return m1.recommended == true }
        
        // Version sort heuristic
        // "Gemini 3" > "Gemini 2"
        // "Pro" > "Flash"
        // "High" > "Low"
        return m1.displayName > m2.displayName // Simple string sort often works for "3" vs "2", but for special suffixes we might need more
    }
    
    private func providerIcon(for provider: String) -> String {
        switch provider {
        case "Google Gemini": return "sparkles"
        case "Anthropic Claude": return "brain.head.profile"
        case "OpenAI GPT": return "bolt.fill"
        default: return "cube.box"
        }
    }
}

struct ModelCard: View {
    let model: AntigravityModelInfo
    @State private var timeRemaining: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    
                    if let provider = model.apiProvider {
                        Text(provider.replacingOccurrences(of: "API_PROVIDER_", with: "").replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                if model.recommended == true {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .font(.caption)
                }
            }
            
            Divider()
            
            // Quota Info
            if let quota = model.quotaInfo {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Quota Remaining")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let frac = quota.remainingFraction {
                            Text("\(Int(frac * 100))%")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(quotaColor(frac))
                        }
                    }
                    
                    if let frac = quota.remainingFraction {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.gray.opacity(0.2))
                                
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(quotaColor(frac))
                                    .frame(width: geo.size.width * CGFloat(frac))
                            }
                        }
                        .frame(height: 6)
                    }
                    
                    if !timeRemaining.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                            Text("Resets in \(timeRemaining)")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                    }
                }
            } else {
                Text("No quota info")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            }
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.1), lineWidth: 1)
        )
        .onAppear {
            updateTimeRemaining()
        }
        .task {
             // Periodically update timer
             while !Task.isCancelled {
                 try? await Task.sleep(nanoseconds: 60 * 1_000_000_000) // 1 min
                 updateTimeRemaining()
             }
        }
    }
    
    private func quotaColor(_ fraction: Double) -> Color {
        if fraction > 0.5 { return .green }
        if fraction > 0.2 { return .orange }
        return .red
    }
    
    private func updateTimeRemaining() {
        guard let resetStr = model.quotaInfo?.resetTime else { return }
        // Format: 2025-12-25T12:33:22Z
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        
        if let date = isoFormatter.date(from: resetStr) {
            let diff = date.timeIntervalSinceNow
            if diff > 0 {
                let formatter = DateComponentsFormatter()
                formatter.allowedUnits = [.hour, .minute]
                formatter.unitsStyle = .abbreviated
                timeRemaining = formatter.string(from: diff) ?? ""
            } else {
                timeRemaining = "Now"
            }
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
    
    // Latency Tracking
    struct LatencyPoint: Identifiable {
        let id = UUID()
        let time: Date
        let latency: Double
    }
    @Published var latencyHistory: [LatencyPoint] = []
    
    // Advanced Metrics
    @Published var currentTPS: Double = 0.0
    @Published var healthScore: Int = 100
    @Published var processSplit: [String: Int64] = ["Antigravity": 0, "Language Server": 0]
    
    @Published var currentAISpeedUp: Int64 = 0
    @Published var currentAISpeedDown: Int64 = 0
    
    // Quota & Discovery
    @Published var quotaStatus: [String: AIQuotaStatus] = [:]
    @Published var discoveryLogs: [String] = []
    
    // New: Authoritative Model List
    @Published var availableModels: [AntigravityModelInfo] = []
    
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
        
        // Model List Update Callback
        AIAnalysisService.shared.onModelListUpdate = { [weak self] models in
            self?.availableModels = models
        }
        
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
        
        // Track Latency (New)
        if usage.latency > 0 {
            updateLatencyHistory(latency: usage.latency)
        }
        
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
    
    private func updateLatencyHistory(latency: TimeInterval) {
        guard latency > 0 else { return }
        let now = Date()
        latencyHistory.append(LatencyPoint(time: now, latency: latency))
        
        // Keep last 50 points
        if latencyHistory.count > 50 {
            latencyHistory.removeFirst()
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

