import SwiftUI

struct AnalysisView: View {
    @ObservedObject private var service = BrowserAnalysisService.shared
    @State private var selectedTabId: String? = "all_requests"
    @State private var selectedRequestId: BrowserRequest.ID? = nil
    @State private var searchText: String = ""
    @State private var selectedTypeFilter: String = "All"
    @State private var sortOrder = [KeyPathComparator(\BrowserRequest.timestamp, order: .reverse)]
    
    let typeFilters = ["All", "Fetch", "XHR", "Image", "Script", "Stylesheet", "Document"]
    
    var body: some View {
        HSplitView {
            // Secondary Sidebar: Tabs List
            VStack(spacing: 0) {
                List(selection: $selectedTabId) {
                    NavigationLink(value: "all_requests") {
                        Label("All Requests", systemImage: "tray.2.fill")
                            .font(.subheadline)
                    }
                    
                    Section("Active Tabs") {
                        ForEach(service.activeTabs) { tab in
                            NavigationLink(value: tab.id) {
                                TabRow(tab: tab)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                
                Divider()
                StatusIndicator()
            }
            .frame(minWidth: 200, maxWidth: 300)
            
            // Main Detail Content
            VStack(spacing: 0) {
                if let tabId = selectedTabId {
                    DetailContent(
                        tabId: tabId,
                        service: service,
                        selectedRequestId: $selectedRequestId,
                        searchText: searchText,
                        typeFilter: selectedTypeFilter,
                        sortOrder: $sortOrder
                    )
                } else {
                    EmptyStateView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .toolbar { toolbarContent }
        }
        .navigationTitle(currentTitle)
    }

    private var currentTitle: String {
        if selectedTabId != "all_requests",
           let tab = service.activeTabs.first(where: { $0.id == selectedTabId }) {
            // Clean title: remove suffixes like " - Google Search"
            let suffixes = [" - ", " | ", " — "]
            var cleanTitle = tab.title
            for suffix in suffixes {
                if let range = cleanTitle.range(of: suffix) {
                    cleanTitle = String(cleanTitle[..<range.lowerBound])
                }
            }
            return cleanTitle
        }
        return "Analysis"
    }
    
    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
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
    @Binding var selectedRequestId: BrowserRequest.ID?
    let searchText: String
    let typeFilter: String
    @Binding var sortOrder: [KeyPathComparator<BrowserRequest>]
    
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
    
    @State private var displayRequests: [BrowserRequest] = []
    @State private var isProcessing = false
    
    var body: some View {
        HSplitView {
            Table(displayRequests, selection: $selectedRequestId, sortOrder: $sortOrder) {
                TableColumn("Status", value: \.sortStatus) { req in
                    StatusIcon(req: req)
                }
                .width(min: 45, ideal: 50, max: 60)
                
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
                }
                .width(min: 75, ideal: 80, max: 100)
                
                TableColumn("Started", value: \.timestamp) { req in
                    Text(formatTableTime(req.timestamp))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .width(min: 100, ideal: 110, max: 130)
                
                TableColumn("URL", value: \.url) { req in
                    HStack(spacing: 4) {
                        if req.responseBody != nil || req.requestBody != nil {
                            Text("📦")
                                .font(.system(size: 9))
                                .help("Payload Captured")
                        } else if req.url.lowercased().hasPrefix("http://") {
                            Text("🔓")
                                .font(.system(size: 9))
                                .help("Plaintext HTTP")
                        }
                        
                        Text(req.url)
                            .font(.system(size: 11))
                            .lineLimit(1)
                    }
                }
                
                TableColumn("Type", value: \.type) { req in
                    TypeBadge(type: req.type)
                }
                .width(min: 70, ideal: 80, max: 100)
                
                TableColumn("Size", value: \.displaySize) { req in
                    Text(formatSize(req.displaySize))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(62) // Slightly wider for 3-digit KB
                
                TableColumn("Time", value: \.sortDuration) { req in
                    Text(formatDuration(req.duration))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(60)
            }
            if let selectedId = selectedRequestId,
               let request = displayRequests.first(where: { $0.id == selectedId }) {
                InspectorView(request: request)
                    .frame(minWidth: 300, idealWidth: 380, maxWidth: .infinity)
                    .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .task(id: service.activeTabs) { updateList() }
        .task(id: searchText) { updateList() }
        .task(id: typeFilter) { updateList() }
        .task(id: sortOrder) { updateList() }
        .task(id: tabId) { updateList() }
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

struct TabRow: View {
    let tab: BrowserTab
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "safari")
                .foregroundStyle(.blue)
                .font(.system(size: 14))
            
            VStack(alignment: .leading, spacing: 0) {
                Text(tab.title)
                    .font(.subheadline)
                    .lineLimit(1)
                Text(tab.url)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if !tab.requests.isEmpty {
                Text("\(tab.requests.count)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.1))
                    .foregroundStyle(.blue)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 2)
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

struct InspectorView: View {
    let request: BrowserRequest
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Inspector")
                    .font(.headline)
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

struct StatusIndicator: View {
    @ObservedObject private var service = BrowserAnalysisService.shared
    
    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Circle()
                    .fill(service.isListening ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(service.isListening ? "Monitoring Active" : "Server Off")
                    .font(.caption2)
                Spacer()
                if let last = service.lastReceived {
                    Text("Conn: \(service.connectionCount) | Last: \(formatShortTime(last))")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }
}

struct SearchField: View {
    @Binding var text: String
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search URL...", text: $text).textFieldStyle(.plain)
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }.buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(6)
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Ready for Traffic Analysis")
                .font(.headline)
            Text("Select a tab or 'All Requests' to begin auditing network sessions.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
    @State private var jsonObject: Any? = nil
    @State private var isFormatting = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isFormatting {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Parsing JSON...").font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 60)
            } else if let json = jsonObject {
                JSONTreeView(value: json)
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
        .task(id: text) {
            isFormatting = true
            jsonObject = await Task.detached(priority: .userInitiated) {
                guard let data = text.data(using: .utf8) else { return nil }
                return try? JSONSerialization.jsonObject(with: data)
            }.value
            isFormatting = false
        }
    }
}

struct JSONTreeView: View {
    let value: Any
    var key: String? = nil
    var depth: Int = 0
    
    var body: some View {
        if let dict = value as? [String: Any] {
            JSONFolderView(key: key, count: dict.count, depth: depth, icon: "curlybraces") {
                let sortedKeys = dict.keys.sorted()
                ForEach(sortedKeys, id: \.self) { k in
                    JSONTreeView(value: dict[k]!, key: k, depth: depth + 1)
                }
            }
        } else if let array = value as? [Any] {
            JSONFolderView(key: key, count: array.count, depth: depth, icon: "text.justify") {
                ForEach(0..<array.count, id: \.self) { i in
                    JSONTreeView(value: array[i], key: "\(i)", depth: depth + 1)
                }
            }
        } else {
            JSONLeafView(key: key, value: value, depth: depth)
        }
    }
}

struct JSONFolderView<Content: View>: View {
    let key: String?
    let count: Int
    let depth: Int
    let icon: String
    let content: () -> Content
    
    @State private var isExpanded = false
    
    init(key: String?, count: Int, depth: Int, icon: String, @ViewBuilder content: @escaping () -> Content) {
        self.key = key
        self.count = count
        self.depth = depth
        self.icon = icon
        self.content = content
        // Default ALL collapsed as requested
        self._isExpanded = State(initialValue: false)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .frame(width: 10)
                    
                    if let key = key {
                        Text("\"\(key)\"")
                            .foregroundStyle(.purple)
                        Text(":")
                    }
                    
                    Image(systemName: icon)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    
                    Text(isExpanded ? "" : "{\(count)}")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .font(.system(size: 11, design: .monospaced))
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    content()
                }
                .padding(.leading, 14)
            }
        }
    }
}

struct JSONLeafView: View {
    let key: String?
    let value: Any
    let depth: Int
    
    var body: some View {
        HStack(spacing: 4) {
            Spacer().frame(width: 14) // Align with chevron space
            
            if let key = key {
                Text("\"\(key)\"")
                    .foregroundStyle(.purple)
                Text(":")
            }
            
            renderValue(value)
        }
        .font(.system(size: 11, design: .monospaced))
    }
    
    @ViewBuilder
    private func renderValue(_ v: Any) -> some View {
        if let s = v as? String {
            Text("\"\(s)\"")
                .foregroundStyle(.green)
                .lineLimit(3)
        } else if let n = v as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                Text(n.boolValue ? "true" : "false")
                    .foregroundStyle(.orange)
            } else {
                Text("\(n)")
                    .foregroundStyle(.blue)
            }
        } else if v is NSNull {
            Text("null")
                .foregroundStyle(.secondary)
                .italic()
        } else {
            Text("\(String(describing: v))")
        }
    }
}

private func formatShortTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    return formatter.string(from: date)
}
