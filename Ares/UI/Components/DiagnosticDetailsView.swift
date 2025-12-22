import SwiftUI

// MARK: - 1. Request Details Sheet
// MARK: - Subcomponents

struct DiagnosticHeader: View {
    let request: BrowserRequest
    @State private var copied = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Status Badge Row
            HStack(spacing: 8) {
                // Status Badge
                Text(getStatusText())
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(getStatusColor().opacity(0.15))
                    .foregroundColor(getStatusColor())
                    .clipShape(Capsule())
                
                if let code = request.statusCode {
                    Text("\(code)")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(code >= 400 ? Color.red : Color.primary)
                }
                
                Spacer()
                
                // Copy URL Button
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(request.url, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        Text(copied ? "Copied" : "Copy URL")
                    }
                    .font(.system(size: 11))
                    .foregroundColor(copied ? Color.green : Color.blue)
                }
                .buttonStyle(.plain)
            }
            
            // URL
            Text(request.url)
                .font(.headline)
                .lineLimit(2)
                .textSelection(.enabled)
            
            // Meta Row
            HStack(spacing: 12) {
                Label(request.method, systemImage: "terminal")
                Label(request.type, systemImage: "doc.text")
                Label("\(request.hitCount) Hits", systemImage: "repeat")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(16)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(12)
    }
    
    private func getStatusText() -> String {
        switch request.status {
        case .success: return "SUCCESS"
        case .error: return "ERROR"
        case .pending: return "PENDING"
        case .active: return "ACTIVE"
        }
    }
    
    private func getStatusColor() -> Color {
        switch request.status {
        case .success: return Color.green
        case .error: return Color.red
        case .pending, .active: return Color.orange
        }
    }
}

struct DiagnosticSection<Content: View>: View {
    let title: String
    let icon: String
    let content: Content
    
    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.primary)
            
            content
                .padding(12)
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(8)
        }
    }
}

struct HitTimelineView: View {
    let hits: [RequestHit]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if hits.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "clock.badge.questionmark")
                        .foregroundColor(.secondary)
                    Text("No detailed hit history available.")
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            } else {
                // Header
                HStack(spacing: 0) {
                    Text("#")
                        .frame(width: 24, alignment: .leading)
                    Text("Time")
                        .frame(width: 100, alignment: .leading)
                    Text("Status")
                        .frame(width: 50, alignment: .center)
                    Text("Duration")
                        .frame(width: 80, alignment: .trailing)
                }
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.secondary)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                
                Divider()
                
                ForEach(Array(hits.enumerated()), id: \.offset) { index, hit in
                    HitRowView(index: index, hit: hit)
                }
            }
        }
        .background(Color.secondary.opacity(0.02))
        .cornerRadius(6)
    }
}

struct HitRowView: View {
    let index: Int
    let hit: RequestHit
    @State private var showBody = false
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("\(index + 1)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 24, alignment: .leading)
                
                Text(formatTime(hit.timestamp))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 80, alignment: .leading)
                
                if let code = hit.statusCode {
                    Text("\(code)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(codeColor(code))
                        .frame(width: 40, alignment: .center)
                } else {
                    Text("...")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                        .frame(width: 40, alignment: .center)
                }
                
                if let dur = hit.duration {
                    Text(String(format: "%.0fms", dur * 1000))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 50, alignment: .trailing)
                } else {
                    Text("-")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .frame(width: 50, alignment: .trailing)
                }
                
                Spacer()
                
                // Body Inspection Button
                if hit.requestBody != nil || hit.responseBody != nil {
                    Button {
                        showBody.toggle()
                    } label: {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 10))
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 8)
                } else {
                    Spacer().frame(width: 16)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(index % 2 == 0 ? Color.clear : Color.secondary.opacity(0.03))
            
            // Expanded Body View
            if showBody {
                VStack(alignment: .leading, spacing: 8) {
                    if let req = hit.requestBody {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Request Body:").font(.caption2).fontWeight(.bold).foregroundColor(.secondary)
                            Text(req)
                                .font(.system(size: 9, design: .monospaced))
                                .lineLimit(10)
                                .padding(6)
                                .background(Color.secondary.opacity(0.05))
                                .cornerRadius(4)
                        }
                    }
                    if let res = hit.responseBody {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Response Body:").font(.caption2).fontWeight(.bold).foregroundColor(.secondary)
                            Text(res)
                                .font(.system(size: 9, design: .monospaced))
                                .lineLimit(10)
                                .padding(6)
                                .background(Color.secondary.opacity(0.05))
                                .cornerRadius(4)
                        }
                    }
                }
                .padding(8)
                .background(Color.blue.opacity(0.05))
            }
        }
    }
    
    private func codeColor(_ code: Int) -> Color {
        if code >= 200 && code < 300 { return Color.green }
        if code >= 400 { return Color.red }
        return Color.secondary
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }
}

struct LatencyAuditView: View {
    let request: BrowserRequest
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let dur = request.duration {
                HStack {
                    Text("Total Time")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.3f s", dur))
                        .fontWeight(.bold)
                        .foregroundColor(getDurationColor(dur))
                }
                
                Text(dur > 0.5 ? "Latency is higher than usual." : "Response time is optimal.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                Text("Timing data incomplete.")
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func getDurationColor(_ dur: Double) -> Color {
        if dur > 1.0 { return Color.red }
        if dur > 0.3 { return Color.orange }
        return Color.green
    }
}

struct PayloadEfficiencyView: View {
    let request: BrowserRequest
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Response Size")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(formatSize(request.displaySize))
                    .font(.caption)
                    .fontWeight(.medium)
            }
            
            if let mime = request.mimeType {
                HStack {
                    Text("MIME Type")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(mime)
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }
            
            if request.displaySize > 1024 * 500 {
                Label("Large payload (>500KB)", systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        }
    }
    
    private func formatSize(_ size: Int) -> String {
        let kb = Double(size) / 1024.0
        if kb > 1024 { return String(format: "%.1f MB", kb / 1024.0) }
        return String(format: "%.1f KB", kb)
    }
}

struct AresInsightsView: View {
    let request: BrowserRequest
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Traffic Burst
            if request.hitCount >= 5 {
                SimpleInsightRow(
                    icon: "bolt.ring.closed",
                    title: "Traffic Burst Detected",
                    description: "Endpoint called \(request.hitCount) times in 5s window.",
                    color: .orange
                )
            }
            
            // Slow Response
            if let dur = request.duration, dur > 1.0 {
                SimpleInsightRow(
                    icon: "tortoise",
                    title: "Slow Response",
                    description: String(format: "Response took %.2fs.", dur),
                    color: .orange
                )
            }
            
            // Error Check
            if let code = request.statusCode, code >= 400 {
                SimpleInsightRow(
                    icon: "exclamationmark.triangle",
                    title: "Request Failed",
                    description: "Status code \(code) indicates an error.",
                    color: .red
                )
            }
            
            // Large Payload
            if request.displaySize > 1024 * 500 {
                SimpleInsightRow(
                    icon: "arrow.down.doc",
                    title: "Large Payload",
                    description: "Response exceeds 500KB.",
                    color: .orange
                )
            }
            
            // All Clear
            if request.hitCount < 5 && (request.statusCode ?? 200) < 400 && (request.duration ?? 0) < 1.0 {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green)
                    Text("No anomalies detected.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
    }
}

struct SimpleInsightRow: View {
    let icon: String
    let title: String
    let description: String
    let color: Color
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.system(size: 14, weight: .bold))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(color)
                Text(description)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(10)
        .background(color.opacity(0.05))
        .cornerRadius(8)
    }
}
