import SwiftUI

struct NetworkInspectorView: View {
    let requestId: String
    @ObservedObject var service = BrowserAnalysisService.shared
    
    // Tab State
    enum InspectorTab: String, CaseIterable, Identifiable {
        case headers = "Headers"
        case payload = "Payload"
        case preview = "Preview"
        case response = "Response"
        case timing = "Timing"
        case ai = "Ares AI" // Feature
        
        var id: String { rawValue }
    }
    
    @State private var selectedTab: InspectorTab = .headers
    
    var request: BrowserRequest? {
        // Search all tabs to find the request by ID
        for tab in service.activeTabs {
            if let req = tab.requests.first(where: { $0.id == requestId }) {
                return req
            }
            // Also check history inside merged requests (though merged POSTs are disabled now, GETs might still have them)
            for req in tab.requests {
                if req.hits.contains(where: { $0.id.uuidString == requestId }) {
                    // Logic to return specific hit would be complex here as we need a BrowserRequest. 
                    // For now, return the parent.
                    return req 
                }
            }
        }
        return nil
    }

    var body: some View {
        Group {
            if let req = request {
                VStack(spacing: 0) {
                    // 1. Top Bar: Overview
                    InspectorHeader(request: req)
                    
                    Divider()
                    
                    // 2. Tab Bar
                    InspectorTabBar(selectedTab: $selectedTab)
                    
                    Divider()
                    
                    // 3. Content Area
                    // 3. Content Area
                    ZStack {
                        Color(nsColor: .textBackgroundColor) // Clean background
                        
                        switch selectedTab {
                        case .headers:
                            HeadersInspector(request: req)
                        case .payload:
                            PayloadInspector(request: req)
                        case .preview:
                            PreviewInspector(request: req)
                        case .response:
                            ResponseInspector(request: req)
                        case .timing:
                            TimingInspector(request: req)
                        case .ai:
                            AresAIInspector(request: req)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text("Request Not Found")
                        .font(.headline)
                    Text("ID: \(requestId)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 1000, minHeight: 700) // Larger default window
        .navigationTitle("Inspect Network Details")
        .onAppear {
            // Hack to attempt maximization (limited in pure SwiftUI, but setting large frame helps)
             if let window = NSApp.windows.first(where: { $0.title == "Inspect Network Details" }) {
                window.zoom(nil) // Toggle zoom (maximize)
            }
        }
    }
}

// MARK: - Components

struct InspectorHeader: View {
    let request: BrowserRequest
    
    var body: some View {
        HStack(spacing: 12) {
            // Method Badge
            Text(request.method)
                .font(.system(size: 11, weight: .bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(methodColor(request.method).opacity(0.1))
                .foregroundColor(methodColor(request.method))
                .cornerRadius(4)
            
            // URL
            Text(request.url)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
            
            Spacer()
            
            // Status Code
            HStack(spacing: 4) {
                Circle()
                    .fill(statusColor(request))
                    .frame(width: 8, height: 8)
                if let code = request.statusCode {
                    Text("\(code)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(statusColor(request))
                } else {
                    Text(request.status.rawValue.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(statusColor(request))
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    private func methodColor(_ method: String) -> Color {
        switch method {
        case "GET": return .green
        case "POST": return .blue
        case "DELETE": return .red
        case "PUT": return .orange
        default: return .secondary
        }
    }
    
    private func statusColor(_ req: BrowserRequest) -> Color {
        if req.status == .error || (req.statusCode ?? 200) >= 400 { return .red }
        if req.status == .pending { return .orange }
        return .green
    }
}

struct InspectorTabBar: View {
    @Binding var selectedTab: NetworkInspectorView.InspectorTab
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(NetworkInspectorView.InspectorTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    ZStack {
                        Rectangle()
                            .fill(selectedTab == tab ? Color(nsColor: .controlBackgroundColor) : Color(nsColor: .windowBackgroundColor))
                        
                        VStack(spacing: 6) {
                            Text(tab.rawValue)
                                .font(.system(size: 13, weight: selectedTab == tab ? .medium : .regular))
                                .foregroundColor(selectedTab == tab ? .primary : .secondary)
                            
                            Rectangle()
                                .fill(selectedTab == tab ? Color.blue : Color.clear)
                                .frame(height: 2)
                        }
                        .padding(.top, 10)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity) // Equal width tabs
            }
        }
        .frame(height: 36)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color(nsColor: .separatorColor)), alignment: .bottom)
    }
}

// MARK: - Inspectors

struct HeadersInspector: View {
    let request: BrowserRequest
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // General
                SectionView(title: "General") {
                    KeyValueRow(key: "Request URL", value: request.url)
                    KeyValueRow(key: "Request Method", value: request.method)
                    KeyValueRow(key: "Status Code", value: "\(request.statusCode ?? 0) \(request.status.rawValue)")
                    KeyValueRow(key: "Remote Address", value: request.remoteAddress ?? "-")
                }
                
                // Response Headers
                if let headers = request.responseHeaders {
                    SectionView(title: "Response Headers") {
                        ForEach(headers.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                            KeyValueRow(key: key, value: value)
                        }
                    }
                }
                
                // Request Headers
                if let headers = request.requestHeaders {
                    SectionView(title: "Request Headers") {
                        ForEach(headers.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                            KeyValueRow(key: key, value: value)
                        }
                    }
                }
            }
            .padding()
        }
    }
}

struct PayloadInspector: View {
    let request: BrowserRequest
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Query String Parameters always on top if present
            if let urlComponents = URLComponents(string: request.url), let items = urlComponents.queryItems, !items.isEmpty {
                ScrollView {
                    VStack(spacing: 20) {
                        SectionView(title: "Query String Parameters") {
                            ForEach(items, id: \.name) { item in
                                KeyValueRow(key: item.name, value: item.value ?? "")
                            }
                        }
                    }
                    .padding()
                }
                .frame(maxHeight: 150) // Limit height for query params
                Divider()
            }
            
            if let body = request.requestBody, !body.isEmpty {
                if body.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") || body.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[") {
                     // Full screen JSON
                     JSONTreeView(jsonString: body)
                 } else {
                     ScrollView {
                         BodyTextView(text: body)
                            .padding()
                     }
                 }
            } else {
                EmptyState(text: "No Request Payload")
            }
        }
    }
}

struct PreviewInspector: View {
    let request: BrowserRequest
    
    var body: some View {
         VStack(alignment: .leading, spacing: 0) {
             if let body = request.responseBody, !body.isEmpty {
                 // Try to guess type
                  if body.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") || body.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[") {
                         JSONTreeView(jsonString: body)
                 } else {
                     ScrollView {
                         Text(body)
                            .font(.system(size: 13, design: .monospaced))
                            .padding()
                     }
                 }
             } else {
                 EmptyState(text: "No Response Data to Preview")
             }
         }
    }
}

struct ResponseInspector: View {
    let request: BrowserRequest
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let body = request.responseBody, !body.isEmpty {
                    SectionView(title: "Response Body (\(formatSize(body.count)))") {
                         Text(body)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(0.05))
                            .cornerRadius(6)
                    }
                } else {
                    EmptyState(text: "No Response Body available")
                }
            }
            .padding()
        }
    }
    
    func formatSize(_ size: Int) -> String {
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}

struct TimingInspector: View {
    let request: BrowserRequest
    
    var body: some View {
        VStack {
            LatencyAuditView(request: request)
            Spacer()
        }
        .padding()
    }
}

struct AresAIInspector: View {
    let request: BrowserRequest
    @State private var copiedCurl = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // 1. Actions
                HStack(spacing: 12) {
                    Button {
                        let curl = generateCurl(request)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(curl, forType: .string)
                        copiedCurl = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiedCurl = false }
                    } label: {
                        Label(copiedCurl ? "Copied cURL" : "Copy as cURL", systemImage: "terminal.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Spacer()
                }
                
                // 2. Security Analysis
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
                
                // 3. Performance Insights
                SectionView(title: "Performance Insights") {
                    AresInsightsView(request: request)
                }
            }
            .padding()
        }
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

// MARK: - Helpers

struct SectionView<Content: View>: View {
    let title: String
    let content: Content
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
            
            content
        }
    }
}

struct KeyValueRow: View {
    let key: String
    let value: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(key + ":")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .trailing)
            
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
            
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

struct EmptyState: View {
    let text: String
    var body: some View {
        VStack {
            Spacer()
            Text(text)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
