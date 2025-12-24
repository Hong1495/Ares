import SwiftUI

struct AnalysisView: View {
    @ObservedObject private var service = BrowserAnalysisService.shared
    @State private var selectedTabId: String? = "all_requests"
    @State private var searchText: String = ""
    @State private var selectedMethods: Set<String> = Set(["GET", "POST", "PUT", "DELETE", "HEAD", "OPTIONS", "PATCH"])
    @State private var selectedTypes: Set<String> = Set(["Fetch", "XHR", "Image", "Script", "Stylesheet", "Document", "CONNECT"])
    @State private var sortOrder = [KeyPathComparator(\BrowserRequest.timestamp, order: .reverse)]
    
    // Sheet State
    @State private var selectedRequest: BrowserRequest? = nil
    @State private var showingDetails = false
    @State private var showingDiagnostics = false
    @State private var showingMethodFilter = false
    @State private var showingTypeFilter = false
    
    let httpMethods = ["CONNECT", "GET", "POST", "PUT", "DELETE", "HEAD", "OPTIONS", "PATCH"]
    let resourceTypes = ["Fetch", "XHR", "Image", "Script", "Stylesheet", "Document", "CONNECT"]
    
    var body: some View {
        // Main Detail Content (Full Width)
        VStack(spacing: 0) {
            DetailContent(
                tabId: "all_requests", // Always show all requests
                service: service,
                searchText: searchText,
                selectedMethods: selectedMethods,
                selectedTypes: selectedTypes,
                sortOrder: $sortOrder,
                selectedRequest: $selectedRequest,
                showingDetails: $showingDetails,
                showingDiagnostics: $showingDiagnostics
            )
        }
        .toolbar { toolbarContent }
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
            
            // HTTP Method Filter
            Button {
                showingMethodFilter.toggle()
            } label: {
                Label {
                    if selectedMethods.isEmpty {
                        Text("No Methods")
                    } else if selectedMethods.count == httpMethods.count {
                        Text("All Methods")
                    } else if selectedMethods.count == 1 {
                        Text(selectedMethods.first!)
                    } else {
                        Text("\(selectedMethods.count) Methods")
                    }
                } icon: {
                    Image(systemName: "arrow.left.arrow.right")
                }
            }
            .popover(isPresented: $showingMethodFilter, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("HTTP Methods")
                        .font(.headline)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                    
                    Button(selectedMethods.count == httpMethods.count ? "Deselect All" : "Select All") {
                        if selectedMethods.count == httpMethods.count {
                            selectedMethods.removeAll()
                        } else {
                            selectedMethods = Set(httpMethods)
                        }
                    }
                    .buttonStyle(.borderless)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    
                    Divider()
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(httpMethods, id: \.self) { method in
                                Button {
                                    if selectedMethods.contains(method) {
                                        selectedMethods.remove(method)
                                    } else {
                                        selectedMethods.insert(method)
                                    }
                                } label: {
                                    HStack {
                                        Image(systemName: selectedMethods.contains(method) ? "checkmark.square.fill" : "square")
                                            .foregroundColor(selectedMethods.contains(method) ? .accentColor : .secondary)
                                        Text(method)
                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                            }
                        }
                    }
                    .frame(maxHeight: 300)
                }
                .frame(width: 200)
            }
            .controlSize(.small)
            
            // Resource Type Filter
            Button {
                showingTypeFilter.toggle()
            } label: {
                Label {
                    if selectedTypes.isEmpty {
                        Text("No Types")
                    } else if selectedTypes.count == resourceTypes.count {
                        Text("All Types")
                    } else if selectedTypes.count == 1 {
                        Text(selectedTypes.first!)
                    } else {
                        Text("\(selectedTypes.count) Types")
                    }
                } icon: {
                    Image(systemName: "doc.text")
                }
            }
            .popover(isPresented: $showingTypeFilter, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Resource Types")
                        .font(.headline)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                    
                    Button(selectedTypes.count == resourceTypes.count ? "Deselect All" : "Select All") {
                        if selectedTypes.count == resourceTypes.count {
                            selectedTypes.removeAll()
                        } else {
                            selectedTypes = Set(resourceTypes)
                        }
                    }
                    .buttonStyle(.borderless)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    
                    Divider()
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(resourceTypes, id: \.self) { type in
                                Button {
                                    if selectedTypes.contains(type) {
                                        selectedTypes.remove(type)
                                    } else {
                                        selectedTypes.insert(type)
                                    }
                                } label: {
                                    HStack {
                                        Image(systemName: selectedTypes.contains(type) ? "checkmark.square.fill" : "square")
                                            .foregroundColor(selectedTypes.contains(type) ? .accentColor : .secondary)
                                        Text(type)
                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                            }
                        }
                    }
                    .frame(maxHeight: 300)
                }
                .frame(width: 200)
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
    let selectedMethods: Set<String>
    let selectedTypes: Set<String>
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
    
    @State private var selectedRequestId: String? = nil
    
    @Environment(\.openWindow) private var openWindow
    
    var filteredRequests: [BrowserRequest] {
        var result = requests
        
        // Filter by search text
        if !searchText.isEmpty {
            result = result.filter { req in
                req.url.localizedCaseInsensitiveContains(searchText) ||
                req.method.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // Filter by HTTP method (if any selected)
        if !selectedMethods.isEmpty {
            result = result.filter { req in
                selectedMethods.contains(req.method)
            }
        }
        
        // Filter by resource type (if any selected)
        if !selectedTypes.isEmpty {
            result = result.filter { req in
                selectedTypes.contains(req.type)
            }
        }
        
        // Sort
        return result.sorted(using: sortOrder)
    }
    
    var body: some View {
        Table(filteredRequests, selection: $selectedRequestId, sortOrder: $sortOrder) {
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


