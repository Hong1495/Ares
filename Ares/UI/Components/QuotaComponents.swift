import SwiftUI
import Combine

struct QuotaMonitorView: View {
    let quotas: [AIQuotaStatus]
    
    var body: some View {
        VStack(spacing: 12) {
            ForEach(quotas) { quota in
                QuotaCard(quota: quota)
            }
        }
        .padding(.vertical, 8)
    }
}

struct QuotaCard: View {
    let quota: AIQuotaStatus
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle()
                    .fill(providerColor(quota.provider))
                    .frame(width: 8, height: 8)
                
                Text(quota.provider)
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Text(quota.model)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)
                
                if isExpired(quota.lastUpdated) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                        .help("Data stale (>5m)")
                }
            }
            
            HStack(spacing: 16) {
                if let reqRem = quota.requestsRemaining, let reqMax = quota.requestsLimit {
                    QuotaRing(
                        title: "Requests",
                        value: reqRem,
                        total: reqMax,
                        reset: quota.requestsResetTime,
                        color: .blue
                    )
                }
                
                if let tokRem = quota.tokensRemaining, let tokMax = quota.tokensLimit {
                    QuotaRing(
                        title: "Tokens",
                        value: tokRem,
                        total: tokMax,
                        reset: quota.tokensResetTime,
                        color: .purple
                    )
                }
                
                // Fallback for Google (Count only)
                if quota.requestsLimit == nil && quota.tokensLimit == nil {
                     VStack(alignment: .leading) {
                        Text("Remaining")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(quota.requestsRemaining ?? 0)")
                            .font(.title2)
                            .monospacedDigit()
                        
                         if let reset = quota.requestsResetTime {
                             TimeRemainingView(target: reset)
                         }
                    }
                }
            }
        }
        .padding()
        .background(Color("CardBackground").opacity(0.5)) // Assuming asset or fallback
        .background(Material.regular)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
    }
    
    func providerColor(_ p: String) -> Color {
        switch p.lowercased() {
        case "openai": return .green
        case "anthropic": return .orange
        case "google": return .blue
        default: return .gray
        }
    }
    
    func isExpired(_ date: Date) -> Bool {
        Date().timeIntervalSince(date) > 300
    }
}

struct QuotaRing: View {
    let title: String
    let value: Int
    let total: Int
    let reset: Date?
    let color: Color
    
    var percent: Double {
        guard total > 0 else { return 0 }
        return Double(value) / Double(total)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.1), lineWidth: 4)
                
                Circle()
                    .trim(from: 0, to: percent)
                    .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                
                Text("\(Int(percent * 100))%")
                    .font(.caption2)
                    .fontWeight(.bold)
            }
            .frame(width: 44, height: 44)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text("\(value) / \(total)")
                    .font(.callout)
                    .fontWeight(.medium)
                    .monospacedDigit()
                
                if let reset = reset {
                    TimeRemainingView(target: reset)
                }
            }
        }
    }
}

struct TimeRemainingView: View {
    let target: Date
    @State private var timeStr = ""
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock")
                .font(.caption2)
            Text(timeStr)
                .font(.caption2)
                .monospacedDigit()
        }
        .foregroundStyle(.secondary)
        .onReceive(timer) { _ in update() }
        .onAppear { update() }
    }
    
    func update() {
        let diff = target.timeIntervalSinceNow
        if diff <= 0 {
            timeStr = "Reset"
        } else if diff < 60 {
            timeStr = String(format: "%.0fs", diff)
        } else if diff < 3600 {
            timeStr = String(format: "%.0fm", diff / 60)
        } else {
            timeStr = String(format: "%.0fh", diff / 3600)
        }
    }
}

struct DiscoveryLogView: View {
    let logs: [String]
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Image(systemName: "ladybug.fill")
                    .foregroundColor(.purple)
                Text("Header Discovery")
                    .font(.headline)
                Spacer()
                Text("\(logs.count) events")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(logs.prefix(20).enumerated()), id: \.offset) { _, log in
                        Text(log)
                            .font(.caption2)
                            .monospaced()
                            .padding(8)
                            .background(Color.black.opacity(0.2))
                            .cornerRadius(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, 4)
            }
            .frame(height: 150)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}
