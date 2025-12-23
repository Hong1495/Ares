import SwiftUI

struct AnalysisInspector: View {
    let request: BrowserRequest
    @State private var copiedCurl = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                // Section 1: Timing & Latency
                VStack(alignment: .leading, spacing: 16) {
                    Text("Timing & Latency")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    LatencyAuditView(request: request)
                }
                
                Divider()
                
                // Section 2: AI Insights & Security
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                         Text("AI Insights & Security")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Spacer()
                        
                        // Action Button (cURL)
                        Button {
                            let curl = generateCurl(request)
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(curl, forType: .string)
                            copiedCurl = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiedCurl = false }
                        } label: {
                            Label(copiedCurl ? "Copied cURL" : "Copy cURL", systemImage: "terminal.fill")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    // Security Analysis
                    SectionView(title: "Security Analysis") {
                        VStack(alignment: .leading, spacing: 8) {
                            if (request.responseHeaders?.keys.contains("Content-Security-Policy") ?? false) {
                                 Label("CSP Enabled", systemImage: "checkmark.shield.fill").foregroundColor(.green)
                            } else {
                                 Label("Missing Content-Security-Policy", systemImage: "exclamationmark.shield").foregroundColor(.orange)
                            }
                            
                             if (request.responseHeaders?.keys.contains("Strict-Transport-Security") ?? false) {
                                 Label("HSTS Enabled", systemImage: "checkmark.shield.fill").foregroundColor(.green)
                            } else {
                                 Label("Missing HSTS Header", systemImage: "exclamationmark.shield").foregroundColor(.orange)
                            }
                        }
                        .padding(12)
                        .background(Color.secondary.opacity(0.05))
                        .cornerRadius(8)
                    }
                    
                    // Performance Insights
                    SectionView(title: "Performance Insights") {
                        AresInsightsView(request: request)
                    }
                }
            }
            .padding(20)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
    
    func generateCurl(_ r: BrowserRequest) -> String {
        var curl = "curl '\(r.url)'"
        curl += " \\\n  -X \(r.method.uppercased())"
        if let headers = r.requestHeaders {
            for (k, v) in headers {
                curl += " \\\n  -H '\(k): \(v)'"
            }
        }
        if let body = r.requestBody, !body.isEmpty {
            // minify body for curl
            curl += " \\\n  --data-raw '\(body.replacingOccurrences(of: "'", with: "'\\''"))'"
        }
        return curl
    }
}
