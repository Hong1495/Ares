import SwiftUI

struct AnalysisInspector: View {
    let request: BrowserRequest
    @State private var copiedCurl = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                
                // 1. Top Summary Cards
                HStack(spacing: 16) {
                    SummaryCard(
                        title: "Status",
                        value: "\(request.statusCode ?? 0)",
                        subtitle: request.status.rawValue.capitalized,
                        icon: "server.rack",
                        color: statusColor
                    )
                    
                    SummaryCard(
                        title: "Time",
                        value: formatDuration(request.duration),
                        subtitle: "Total Latency",
                        icon: "clock",
                        color: .blue
                    )
                    
                    SummaryCard(
                        title: "Size",
                        value: ByteCountFormatter.string(fromByteCount: Int64(request.size ?? 0), countStyle: .file),
                        subtitle: compressionStatus,
                        icon: "arrow.down.circle",
                        color: .purple
                    )
                }
                .frame(maxWidth: .infinity)
                
                Divider()
                
                // 2. Network & Traffic Insights
                VStack(alignment: .leading, spacing: 12) {
                    Label("Traffic Analysis", systemImage: "network")
                        .font(.headline)
                    
                    VStack(spacing: 0) {
                        InsightRow(key: "Remote Address", value: request.remoteAddress ?? "Unknown")
                        Divider()
                        InsightRow(key: "Protocol", value: "HTTP/1.1 (Proxied)") // MITM typically proxies as 1.1/2
                        Divider()
                        InsightRow(key: "Content Method", value: request.method)
                        Divider()
                        InsightRow(key: "Security Protocol", value: request.url.hasPrefix("https") ? "TLS 1.2/1.3" : "Unencrypted HTTP", valueColor: request.url.hasPrefix("https") ? .green : .red)
                        Divider()
                        InsightRow(key: "Cache Status", value: cacheStatus, valueColor: cacheColor)
                    }
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.1)))
                }
                
                // 3. Smart Diagnostics (Combined Security & Perf)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Smart Diagnostics", systemImage: "stethoscope")
                            .font(.headline)
                        Spacer()
                        Text("\(diagnostics.count) checks")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    if diagnostics.isEmpty {
                        HStack {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(.green)
                            Text("No obvious issues detected.")
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.green.opacity(0.05))
                        .cornerRadius(8)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(diagnostics, id: \.id) { diag in
                                DiagnosticRow(diagnostic: diag)
                            }
                        }
                    }
                }
                
                // 4. Actions
                HStack {
                    Spacer()
                    Button {
                        let curl = request.generateCurl()
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(curl, forType: .string)
                        copiedCurl = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiedCurl = false }
                    } label: {
                        HStack {
                            Image(systemName: copiedCurl ? "checkmark" : "terminal")
                            Text(copiedCurl ? "Copied Command" : "Copy as cURL")
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)
                    .tint(.primary)
                }
                
            }
            .padding(24)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
    
    // MARK: - Computed Helpers
    
    private var statusColor: Color {
        guard let code = request.statusCode else { return .orange }
        if code < 300 { return .green }
        if code < 400 { return .blue }
        return .red
    }
    
    private var compressionStatus: String {
        let headers = request.responseHeaders ?? [:]
        if let encoding = headers.first(where: { $0.key.lowercased() == "content-encoding" })?.value {
            return "Encoded: \(encoding)"
        }
        return "No Compression"
    }
    
    private var cacheStatus: String {
        if request.statusCode == 304 { return "HIT (Revalidated)" }
        let headers = request.responseHeaders ?? [:]
        if let cache = headers.first(where: { $0.key.lowercased() == "cache-control" })?.value {
            if cache.contains("no-store") { return "No Store" }
            if cache.contains("no-cache") { return "No Cache (Revalidate)" }
            if cache.contains("max-age") { return "Cacheable" }
        }
        return "Unknown / Miss"
    }
    
    private var cacheColor: Color {
        let status = cacheStatus
        if status.contains("HIT") || status.contains("Cacheable") { return .green }
        if status.contains("No") { return .orange }
        return .secondary
    }
    
    private func formatDuration(_ duration: Double?) -> String {
        guard let d = duration else { return "-" }
        if d < 1.0 {
            return String(format: "%.0f ms", d * 1000)
        }
        return String(format: "%.2f s", d)
    }
    
    // MARK: - Diagnostics Engine
    
    struct DiagnosticItem: Identifiable {
        let id = UUID()
        let type: DiagnosticType
        let title: String
        let description: String
        
        enum DiagnosticType {
            case error, warning, info
            
            var color: Color {
                switch self {
                case .error: return .red
                case .warning: return .orange
                case .info: return .blue
                }
            }
            
            var icon: String {
                switch self {
                case .error: return "exclamationmark.triangle.fill"
                case .warning: return "exclamationmark.circle.fill"
                case .info: return "info.circle.fill"
                }
            }
        }
    }
    
    private var diagnostics: [DiagnosticItem] {
        var items: [DiagnosticItem] = []
        let headers = request.responseHeaders ?? [:]
        let keys = headers.keys.map { $0.lowercased() }
        
        // Security Checks
        if !keys.contains("start-transport-security") && request.url.hasPrefix("https") {
            // HSTS
             // Strict-Transport-Security name check (typo in logic above intent? standard header is Strict-Transport-Security)
        }
        if !keys.contains("strict-transport-security") && request.url.hasPrefix("https") {
             items.append(DiagnosticItem(type: .warning, title: "Missing HSTS", description: "Enforce HTTPS to prevent downgrade attacks."))
        }
        if !keys.contains("content-security-policy") {
             items.append(DiagnosticItem(type: .info, title: "Missing CSP", description: "Content Security Policy helps prevent XSS attacks."))
        }
        
        // Performance Checks
        if let s = request.size, s > 100_000, !compressionStatus.contains("Encoded") {
             items.append(DiagnosticItem(type: .warning, title: "Uncompressed Large content", description: "Response > 100KB serves without Gzip/Brotli."))
        }
        
        if (request.duration ?? 0) > 1.0 {
            items.append(DiagnosticItem(type: .warning, title: "High Latency", description: "Request took over 1 second. Inspect server processing time."))
        }
        
        return items
    }
}

// MARK: - Components

struct SummaryCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.primary)
            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.1)))
    }
}

struct InsightRow: View {
    let key: String
    let value: String
    var valueColor: Color = .primary
    
    var body: some View {
        HStack {
            Text(key)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .leading)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(valueColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

struct DiagnosticRow: View {
    let diagnostic: AnalysisInspector.DiagnosticItem
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: diagnostic.type.icon)
                .foregroundColor(diagnostic.type.color)
                .font(.title3)
                .padding(.top, 2)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(diagnostic.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Text(diagnostic.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(12)
        .background(diagnostic.type.color.opacity(0.05))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(diagnostic.type.color.opacity(0.2), lineWidth: 1))
    }
}
