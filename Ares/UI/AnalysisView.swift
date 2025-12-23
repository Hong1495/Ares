import SwiftUI

struct AnalysisView: View {
    @ObservedObject private var service = BrowserAnalysisService.shared
    @State private var selectedTabId: String? = "all_requests"
    @State private var searchText: String = ""
    @State private var selectedTypeFilter: String = "All"
    @State private var sortOrder = [KeyPathComparator(\BrowserRequest.timestamp, order: .reverse)]
    
    // Sheet State
    @State private var selectedRequest: BrowserRequest? = nil
    @State private var showingDetails = false
    @State private var showingDiagnostics = false
    
    let typeFilters = ["All", "Fetch", "XHR", "Image", "Script", "Stylesheet", "Document"]
    
    var body: some View {
        HSplitView {
            // Secondary Sidebar: Tabs List
            VStack(spacing: 0) {
                List(selection: $selectedTabId) {
                    Group {
                        NavigationLink(value: "all_requests") {
                            Label("All Requests", systemImage: "clock.arrow.circlepath")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(selectedTabId == "all_requests" ? Color.primary : Color.secondary)
                        }
                        .padding(.vertical, 4)
                        
                        Text("Active Tabs")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 16)
                            .padding(.bottom, 8)
                            .padding(.leading, 4)
                        
                        if service.activeTabs.isEmpty {
                            Text("No tabs active")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .padding(.leading, 12)
                        } else {
                            ForEach(service.activeTabs) { tab in
                                NavigationLink(value: tab.id) {
                                    TabRow(tab: tab, isSelected: selectedTabId == tab.id)
                                }
                                .listRowSeparator(.hidden)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollIndicators(.hidden)
                
                StatusIndicator()
            }
            .frame(minWidth: 220, maxWidth: 350)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.3))
            
            // Main Detail Content
            VStack(spacing: 0) {
                if let tabId = selectedTabId {
                    DetailContent(
                        tabId: tabId,
                        service: service,
                        searchText: searchText,
                        typeFilter: selectedTypeFilter,
                        sortOrder: $sortOrder,
                        selectedRequest: $selectedRequest,
                        showingDetails: $showingDetails,
                        showingDiagnostics: $showingDiagnostics
                    )
                } else {
                    EmptyStateView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .toolbar { toolbarContent }
        }
        .navigationTitle("Analysis")
    }
    
    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            // Start/Stop Listening Toggle
            Toggle(isOn: Binding(
                get: { service.isListening },
                set: { _ in service.toggleListening() }
            )) {
                EmptyView()
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .help(service.isListening ? "Stop Listening" : "Start Listening")
            
            Divider()
            
            Picker("Type", selection: $selectedTypeFilter) {
                ForEach(typeFilters, id: \.self) { type in
                    Text(type).tag(type)
                }
            }
            .controlSize(.small)
            
            SearchField(text: $searchText)
                .frame(width: 200)
            
            Button(action: { service.activeTabs.removeAll() }) {
                Label("Clear", systemImage: "trash")
            }
            .buttonStyle(.borderless)
            .help("Clear All Data")
        }
    }
}

struct DetailContent: View {
    let tabId: String
    @ObservedObject var service: BrowserAnalysisService
    let searchText: String
    let typeFilter: String
    @Binding var sortOrder: [KeyPathComparator<BrowserRequest>]
    
    @Binding var selectedRequest: BrowserRequest?
    @Binding var showingDetails: Bool
    @Binding var showingDiagnostics: Bool
    
    var requests: [BrowserRequest] {
        if tabId == "all_requests" {
            // Use a slightly more efficient approach for large flattened arrays
            // only if tabId actually changed or service updated
            return service.activeTabs.flatMap { $0.requests }
        } else {
            // Optimize lookup for single tab
            return service.activeTabs.first(where: { $0.id == tabId })?.requests ?? []
        }
    }
    
    private var tabTitle: String {
        if tabId == "all_requests" { return "All Requests" }
        if let tab = service.activeTabs.first(where: { $0.id == tabId }) {
            return tab.title.isEmpty ? "Untitled Tab" : tab.title
        }
        return "Unknown Tab"
    }
    
    @State private var displayRequests: [BrowserRequest] = []
    @State private var isProcessing = false
    @State private var selectedRequestId: String? = nil
    
    @Environment(\.openWindow) private var openWindow
    
    var body: some View {
        Table(displayRequests, selection: $selectedRequestId, sortOrder: $sortOrder) {
            TableColumn("Status", value: \.sortStatus) { req in
                StatusIcon(req: req)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .contextMenu { tableRowContextMenu(req) }
            }
            .width(min: 45, ideal: 50, max: 60)
            
            TableColumn("Sec", value: \.url) { req in
                if req.url.lowercased().hasPrefix("https") {
                    Image(systemName: "lock.fill") // Secure
                        .font(.system(size: 10))
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "lock.open.fill") // Insecure
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                }
            }
            .width(30)
            
            TableColumn("Method", value: \.method) { req in
                HStack(spacing: 4) {
                    Text(req.method)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(methodColor(req.method))
                    
                    if req.hitCount > 1 {
                        Text("\(req.hitCount)")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.8))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .contextMenu { tableRowContextMenu(req) }
            }
            .width(min: 75, ideal: 80, max: 100)
            
            TableColumn("Started", value: \.timestamp) { req in
                Text(formatTableTime(req.timestamp))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .contextMenu { tableRowContextMenu(req) }
            }
            .width(min: 100, ideal: 110, max: 130)
            
            TableColumn("URL", value: \.url) { req in
                HStack(spacing: 4) {
                    if req.responseBody != nil || req.requestBody != nil {
                        Text("📦")
                            .font(.system(size: 9))
                            .help("Payload Captured")
                    } else if req.url.lowercased().hasPrefix("http://") {
                         // Removed confusing lock icon for HTTP plaintext
                    }
                    
                    Text(req.url)
                        .font(.system(size: 11))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .contextMenu { tableRowContextMenu(req) }
            }
            
            TableColumn("Type", value: \.type) { req in
                TypeBadge(type: req.type)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .contextMenu { tableRowContextMenu(req) }
            }
            .width(min: 70, ideal: 80, max: 100)
            
            TableColumn("Size", value: \.displaySize) { req in
                Text(formatSize(req.displaySize))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .contentShape(Rectangle())
                    .contextMenu { tableRowContextMenu(req) }
            }
            .width(62)
            
            TableColumn("Time", value: \.sortDuration) { req in
                Text(formatDuration(req.duration))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .contentShape(Rectangle())
                    .contextMenu { tableRowContextMenu(req) }
            }
            .width(60)
        }

        .task(id: service.activeTabs) { updateList() }
        .task(id: searchText) { updateList() }
        .task(id: typeFilter) { updateList() }
        .task(id: sortOrder) { updateList() }
        .task(id: tabId) { updateList() }
    }
    
    @ViewBuilder
    private func tableRowContextMenu(_ req: BrowserRequest) -> some View {
        Button {
            // New Window Action
            openWindow(id: "network-inspector", value: req.id)
        } label: {
            Label("Inspect Network Details", systemImage: "macwindow.badge.plus")
        }

        
        Button {
            selectedRequestId = req.id
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(req.url, forType: .string)
        } label: {
            Label("Copy URL", systemImage: "doc.on.doc")
        }
        
        Button {
            let curl = req.generateCurl()
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(curl, forType: .string)
        } label: {
            Label("Copy as cURL", systemImage: "terminal")
        }
    }
    
    private func updateList() {
        let raw = requests
        let filter = searchText
        let type = typeFilter
        let order = sortOrder
        
        // Background sorting to keep UI responsive
        Task.detached(priority: .userInitiated) {
            let filtered = raw.filter { req in
                let matchesSearch = filter.isEmpty || req.url.localizedCaseInsensitiveContains(filter)
                let matchesType: Bool
                let t = req.type.lowercased()
                if type == "All" { matchesType = true }
                else if type == "XHR" { matchesType = t.contains("xmlhttprequest") || t.contains("xhr") }
                else if type == "Fetch" { matchesType = t.contains("fetch") }
                else if type == "Image" { matchesType = t.contains("image") || t.contains("svg") }
                else if type == "Script" { matchesType = t.contains("script") }
                else if type == "Stylesheet" { matchesType = t.contains("stylesheet") || t.contains("css") }
                else if type == "Document" { matchesType = t.contains("main_frame") || t.contains("sub_frame") || t.contains("document") }
                else { matchesType = t.contains(type.lowercased()) }
                return matchesSearch && matchesType
            }.sorted(using: order)
            
            await MainActor.run {
                self.displayRequests = filtered
            }
        }
    }
    
    private func methodColor(_ method: String) -> Color {
        switch method.uppercased() {
        case "GET": return .green
        case "POST": return .blue
        case "PUT": return .orange
        case "DELETE": return .red
        default: return .gray
        }
    }
    
    private func formatSize(_ size: Int?) -> String {
        guard let size = size, size > 0 else { return "-" }
        let kb = Double(size) / 1024.0
        if kb > 1024 { return String(format: "%.1fMB", kb / 1024.0) }
        return String(format: "%.0fKB", kb)
    }
    
    private func formatDuration(_ s: Double?) -> String {
        guard let s = s, s > 0 else { return "-" }
        if s < 1.0 { return String(format: "%.0fms", s * 1000) }
        return String(format: "%.2fs", s)
    }
    
    private func formatTableTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }
}


