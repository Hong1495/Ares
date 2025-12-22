import SwiftUI

// MARK: - Shared Views

struct TabRow: View {
    let tab: BrowserTab
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "safari")
                .font(.system(size: 14))
                .foregroundStyle(isSelected ? Color.blue : Color.secondary)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(tab.title.isEmpty ? "Untitled Tab" : tab.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.8))
                    .lineLimit(1)
                
                Text(tab.url)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.secondary.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            
            Spacer(minLength: 4)
            
            if !tab.requests.isEmpty {
                Text("\(tab.requests.count)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(isSelected ? Color.white.opacity(0.2) : Color.blue.opacity(0.1))
                    .foregroundStyle(isSelected ? .white : .blue)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

struct StatusIcon: View {
    let req: BrowserRequest
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            
            if let code = req.statusCode {
                Text("\(code)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(code >= 400 ? .red : .secondary)
            }
        }
    }
    
    private var color: Color {
        switch req.status {
        case .pending, .active: return .orange
        case .success: return .green
        case .error: return .red
        }
    }
}

struct TypeBadge: View {
    let type: String
    
    var body: some View {
        Text(type.uppercased())
            .font(.system(size: 8, weight: .bold))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.15))
            .foregroundStyle(.secondary)
            .cornerRadius(3)
    }
}

// MARK: - Inspector & Payload Views

struct InspectorView: View {
    let request: BrowserRequest
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(request.url)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if request.hitCount > 1 {
                    Text("\(request.hitCount) hits")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                }
            }
            .padding()
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    DetailSection(title: "Overview") {
                        DetailRow(label: "URL", value: request.url)
                        DetailRow(label: "Remote Address", value: request.remoteAddress ?? "Unknown")
                        DetailRow(label: "Method", value: request.method)
                        DetailRow(label: "Status", value: "\(request.status.rawValue.uppercased()) \(request.statusCode.map { "(\($0))" } ?? "")")
                    }
                    
                    if let requestHeaders = request.requestHeaders, !requestHeaders.isEmpty {
                        DetailSection(title: "Request Headers") {
                            HeaderListView(headers: requestHeaders)
                        }
                    }
                    
                    if let responseHeaders = request.responseHeaders, !responseHeaders.isEmpty {
                        DetailSection(title: "Response Headers") {
                            HeaderListView(headers: responseHeaders)
                        }
                    }
                    
                    DetailSection(title: "Timing") {
                        DetailRow(label: "Started", value: formatFullTime(request.timestamp))
                        if let dur = request.duration {
                            DetailRow(label: "Duration", value: String(format: "%.3f s", dur))
                            WaterfallView(duration: dur)
                                .frame(height: 20)
                                .padding(.top, 4)
                        }
                    }
                    
                    if !request.hits.isEmpty {
                        DetailSection(title: "Hit History") {
                            HitTimelineView(hits: request.hits)
                        }
                    }
                    
                    if request.requestBody != nil || request.responseBody != nil {
                        DetailSection(title: "Payload") {
                            PayloadView(request: request)
                        }
                    }
                    
                    if let error = request.errorMessage {
                        DetailSection(title: "Error Log") {
                            Text(error)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.red)
                                .padding(8)
                                .background(Color.red.opacity(0.05))
                                .cornerRadius(4)
                        }
                    }
                }
                .padding()
            }
        }
    }
    
    private func formatFullTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }
}

struct HeaderListView: View {
    let headers: [String: String]
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(headers.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                HStack(alignment: .top) {
                    Text(key)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 100, alignment: .leading)
                    Text(value)
                        .font(.system(size: 10))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(6)
    }
}

struct WaterfallView: View {
    let duration: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(maxWidth: .infinity)
                
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.blue.opacity(0.6))
                    .frame(width: geo.size.width * CGFloat(min(duration, 5.0) / 5.0)) // Max 5s scale
            }
        }
    }
}

struct DetailSection<Content: View>: View {
    let title: String
    let content: Content
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
            content
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 11))
                .textSelection(.enabled)
                .lineLimit(5)
        }
    }
}

struct PayloadView: View {
    let request: BrowserRequest
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let reqBody = request.requestBody, !reqBody.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "Request Body", content: reqBody)
                        BodyTextView(text: reqBody)
                    }
                }
                
                if let resBody = request.responseBody, !resBody.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "Response Body", content: resBody)
                        BodyTextView(text: resBody)
                    }
                }
            }
            .padding()
        }
    }
}

struct SectionHeader: View {
    let title: String
    let content: String
    @State private var copied = false
    
    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(content, forType: .string)
                withAnimation {
                    copied = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    copied = false
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    Text(copied ? "Copied" : "Copy")
                }
                .font(.system(size: 10))
                .foregroundStyle(copied ? .green : .blue)
            }
            .buttonStyle(.plain)
        }
    }
}

struct BodyTextView: View {
    let text: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Check if it looks like JSON
            if text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") ||
               text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[") {
                JSONTreeView(jsonString: text)
                    .padding(8)
            } else {
                Text(text)
                    .font(.system(size: 10, design: .monospaced))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(6)
    }
}



struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

struct StatusIndicator: View {
    @ObservedObject private var service = BrowserAnalysisService.shared
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: service.activeTabs.isEmpty ? "antenna.radiowaves.left.and.right.slash" : "antenna.radiowaves.left.and.right")
                .font(.system(size: 10, weight: .light))
                .foregroundStyle(service.activeTabs.isEmpty ? Color.secondary : Color.green)
            
            Circle()
                .fill(service.activeTabs.isEmpty ? Color.secondary : Color.green)
                .frame(width: 6, height: 6)
            
            Text(service.activeTabs.isEmpty ? "No active sessions" : "Monitoring Network Traffic")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(10)
        .background(Color.secondary.opacity(0.03))
    }
}

struct SearchField: View {
    @Binding var text: String
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
            TextField("Search...", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 32, weight: .ultraLight))
                .foregroundStyle(.tertiary)
            Text("No Activity Captured")
                .font(.system(size: 13, weight: .medium))
            Text("Network requests for this tab will appear here in real-time.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 200)
        }
        .opacity(0.6)
    }
}

func formatShortNetworkTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    return formatter.string(from: date)
}
