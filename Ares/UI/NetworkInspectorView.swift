import SwiftUI

struct NetworkInspectorView: View {
    let requestId: String
    @ObservedObject var service = BrowserAnalysisService.shared

    // Tab State
    enum InspectorTab: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case headers = "Headers"
        case payload = "Payload"
        case preview = "Preview"
        case response = "Response"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .overview: return "chart.bar.doc.horizontal"
            case .headers: return "list.bullet.rectangle"
            case .payload: return "doc.text.magnifyingglass"
            case .preview: return "eye"
            case .response: return "arrow.down.circle"
            }
        }
    }

    @State private var selectedTab: InspectorTab = .overview

    var request: BrowserRequest? {
        // Search all tabs to find the request by ID
        for tab in service.activeTabs {
            if let req = tab.requests.first(where: { $0.id == requestId }) {
                return req
            }
            // Also check history even if merged
            for req in tab.requests {
                if req.hits.contains(where: { $0.id.uuidString == requestId }) {
                    return req
                }
            }
        }
        return nil
    }

    var body: some View {
        Group {
            if let req = request {
                NavigationSplitView {
                    List(InspectorTab.allCases, selection: $selectedTab) { tab in
                        NavigationLink(value: tab) {
                            Label(tab.rawValue, systemImage: tab.icon)
                        }
                    }
                    .listStyle(.sidebar)
                    .navigationTitle("Inspector")
                } detail: {
                    VStack(spacing: 0) {
                        // Header
                        InspectorHeader(request: req)
                        Divider()

                        // Main Inspector Content
                        ZStack {
                            Color(nsColor: .textBackgroundColor) // Clean background

                            switch selectedTab {
                            case .overview:
                                AnalysisInspector(request: req)
                            case .headers:
                                HeadersInspector(request: req)
                            case .payload:
                                PayloadInspector(request: req)
                            case .preview:
                                PreviewInspector(request: req)
                            case .response:
                                ResponseInspector(request: req)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
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
        .frame(minWidth: 1000, minHeight: 700)
        .navigationTitle("Inspect Network Details")
        .onAppear {
             if let window = NSApp.windows.first(where: { $0.title == "Inspect Network Details" }) {
                window.zoom(nil)
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
                .font(DS.Typography.metadata.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(methodColor(request.method).opacity(0.1))
                .foregroundColor(methodColor(request.method))
                .cornerRadius(4)

            // URL
            Text(request.url)
                .font(DS.Typography.body.weight(.medium))
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
                        .font(DS.Typography.secondary.weight(.semibold))
                        .foregroundColor(statusColor(request))
                } else {
                    Text(request.status.rawValue.uppercased())
                        .font(DS.Typography.caption.weight(.semibold))
                        .foregroundColor(statusColor(request))
                }
            }
        }
        .padding(12)
        .background(DS.canvas)
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
// MARK: - Inspectors
