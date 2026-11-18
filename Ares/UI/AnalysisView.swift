import SwiftUI

struct AnalysisView: View {
    @ObservedObject private var service = BrowserAnalysisService.shared
    @Environment(\.openWindow) private var openWindow
    @State private var searchText = ""
    @State private var selectedRequestID: String?
    @State private var showingFilters = false
    @State private var confirmingClear = false
    @State private var selectedMethods = Set(Self.httpMethods)
    @State private var selectedTypes = Set(Self.resourceTypes)
    @State private var sortOrder = [KeyPathComparator(\BrowserRequest.timestamp, order: .reverse)]

    private static let httpMethods = ["CONNECT", "GET", "POST", "PUT", "DELETE", "HEAD", "OPTIONS", "PATCH"]
    private static let resourceTypes = ["Fetch", "XHR", "Image", "Script", "Stylesheet", "Document", "Font", "Media", "WebSocket", "Other"]

    var body: some View {
        let captured = service.activeTabs.flatMap(\.requests)
        let visible = captured.filter { request in
            selectedMethods.contains(request.method) && selectedTypes.contains(request.type) &&
                (searchText.isEmpty || request.url.localizedCaseInsensitiveContains(searchText) ||
                 request.method.localizedCaseInsensitiveContains(searchText) || request.type.localizedCaseInsensitiveContains(searchText))
        }
        let inspected = visible.first { $0.id == selectedRequestID }
        return VStack(spacing: 0) {
            WorkspaceControls(placeholder: "Search requests", search: $searchText) {
                Toggle("Listen", isOn: Binding(get: { service.isListening }, set: { _ in service.toggleListening() }))
                    .toggleStyle(.switch).help("Listen for browser requests")
            } actions: {
                WorkspaceAction(title: filterCount == 0 ? "Filters" : "Filters (\(filterCount))", symbol: "line.3.horizontal.decrease.circle") {
                    showingFilters.toggle()
                }.popover(isPresented: $showingFilters, arrowEdge: .bottom) { filters }
                WorkspaceAction(title: "Inspect", symbol: "macwindow", primary: true) {
                    if let inspected { openWindow(id: "network-inspector", value: inspected.id) }
                }.disabled(inspected == nil).help("Select a request to inspect its details")
                Menu {
                    Button("Clear Requests…", role: .destructive) { confirmingClear = true }
                        .disabled(captured.isEmpty)
                } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("Analysis actions")
            }.padding(.horizontal, DS.Space.lg).padding(.top, DS.Space.pageTop).padding(.bottom, DS.Space.md)

            Divider()
            DetailContent(requests: visible, hasCapturedRequests: !captured.isEmpty, isListening: service.isListening,
                          sortOrder: $sortOrder, selectedRequestId: $selectedRequestID)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(DS.canvas)
        .navigationTitle("")
        .toolbar { CollectionTitleToolbar(title: "Analysis", count: captured.count, unit: "Requests") }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 12) {
                if visible.count != captured.count { Text("\(visible.count) shown") }
                Label("\(captured.filter { $0.status == .success }.count) successful", systemImage: "checkmark.circle")
                Label("\(captured.filter { $0.status == .error }.count) errors", systemImage: "exclamationmark.circle")
                Spacer(minLength: 4)
                let bytes = captured.reduce(Int64(0)) { $0 + Int64($1.displaySize) }
                Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) + " transferred")
            }.font(DS.Typography.metadata.monospacedDigit()).foregroundStyle(.secondary)
                .padding(.horizontal, DS.Space.lg).padding(.vertical, DS.Space.sm).background(DS.canvas)
        }
        .confirmationDialog("Clear all captured requests?", isPresented: $confirmingClear) {
            Button("Clear Requests", role: .destructive) { service.activeTabs.removeAll(); selectedRequestID = nil }
        }
    }

    private var filterCount: Int {
        (selectedMethods.count == Self.httpMethods.count ? 0 : 1) + (selectedTypes.count == Self.resourceTypes.count ? 0 : 1)
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack {
                Text("Request Filters").font(DS.Typography.body.weight(.medium))
                Spacer()
                Button("Reset") { selectedMethods = Set(Self.httpMethods); selectedTypes = Set(Self.resourceTypes) }
                    .disabled(filterCount == 0)
            }
            HStack(alignment: .top, spacing: DS.Space.xl) {
                filterColumn("HTTP Method", values: Self.httpMethods, selection: $selectedMethods)
                filterColumn("Resource Type", values: Self.resourceTypes, selection: $selectedTypes)
            }
        }.controlSize(.small).font(DS.Typography.secondary).padding(DS.Space.lg).frame(minWidth: 280)
    }

    private func filterColumn(_ title: String, values: [String], selection: Binding<Set<String>>) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text(title).foregroundStyle(.secondary)
            Button(selection.wrappedValue.count == values.count ? "Deselect All" : "Select All") {
                selection.wrappedValue = selection.wrappedValue.count == values.count ? [] : Set(values)
            }.buttonStyle(.borderless)
            ForEach(values, id: \.self) { value in
                Toggle(value, isOn: Binding(get: { selection.wrappedValue.contains(value) }, set: { enabled in
                    if enabled { selection.wrappedValue.insert(value) } else { selection.wrappedValue.remove(value) }
                })).toggleStyle(.checkbox)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DetailContent: View {
    let requests: [BrowserRequest]
    let hasCapturedRequests: Bool
    let isListening: Bool
    @Binding var sortOrder: [KeyPathComparator<BrowserRequest>]
    @Binding var selectedRequestId: String?
    @Environment(\.openWindow) private var openWindow

    private var filteredRequests: [BrowserRequest] { requests.sorted(using: sortOrder) }

    var body: some View {
        if filteredRequests.isEmpty {
            ContentUnavailableView {
                Label(emptyTitle, systemImage: emptyIcon)
            } description: {
                Text(emptyDescription)
            }
        } else {
            Table(filteredRequests, selection: $selectedRequestId, sortOrder: $sortOrder) {
                TableColumn("Status", value: \.sortStatus) { req in
                    StatusIcon(req: req)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .width(min: 45, ideal: 50, max: 60)

                TableColumn("Sec", value: \.url) { req in
                    if req.url.lowercased().hasPrefix("https") {
                        Image(systemName: "lock.fill") // Secure
                            .font(DS.Typography.caption)
                            .foregroundStyle(.green)
                    } else {
                        Image(systemName: "lock.open.fill") // Insecure
                            .font(DS.Typography.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .width(30)

                TableColumn("Method", value: \.method) { req in
                    HStack(spacing: 4) {
                        Text(req.method)
                            .font(DS.Typography.metadata.monospaced().weight(.semibold))
                            .foregroundStyle(methodColor(req.method))

                        if req.hitCount > 1 {
                            Text("\(req.hitCount)")
                                .font(DS.Typography.caption.monospaced().weight(.semibold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.orange.opacity(0.8))
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .width(min: 75, ideal: 80, max: 100)

                TableColumn("Started", value: \.timestamp) { req in
                    Text(formatTableTime(req.timestamp))
                        .font(DS.Typography.metadata.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .width(min: 100, ideal: 110, max: 130)

                TableColumn("URL", value: \.url) { req in
                    HStack(spacing: 4) {
                        if req.responseBody != nil || req.requestBody != nil {
                            Image(systemName: "shippingbox").foregroundStyle(.secondary)
                                .font(DS.Typography.caption)
                                .help("Payload Captured")
                        }

                        Text(req.url)
                            .font(DS.Typography.metadata)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }

                TableColumn("Type", value: \.type) { req in
                    TypeBadge(type: req.type)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .width(min: 70, ideal: 80, max: 100)

                TableColumn("Size", value: \.displaySize) { req in
                    Text(formatSize(req.displaySize))
                        .font(DS.Typography.metadata.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .width(62)

                TableColumn("Time", value: \.sortDuration) { req in
                    Text(formatDuration(req.duration))
                        .font(DS.Typography.metadata.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .width(60)
            }
            .scrollIndicators(.never)
            .contextMenu(forSelectionType: String.self) { selection in
                if selection.count == 1, let request = requests.first(where: { selection.contains($0.id) }) {
                    tableRowContextMenu(request)
                }
            } primaryAction: { selection in
                if selection.count == 1, let id = selection.first {
                    openWindow(id: "network-inspector", value: id)
                }
            }
        }
    }

    private var emptyTitle: String {
        if !isListening && !hasCapturedRequests { return "Analysis listener is stopped" }
        return hasCapturedRequests ? "No matching requests" : "No requests captured"
    }

    private var emptyIcon: String {
        isListening || hasCapturedRequests ? "network.slash" : "pause.circle"
    }

    private var emptyDescription: String {
        if !isListening && !hasCapturedRequests { return "Turn on Listen to capture browser traffic." }
        if !hasCapturedRequests { return "Captured requests will appear here." }
        return "Change the search or filter selection to show requests."
    }
    
    @ViewBuilder
    private func tableRowContextMenu(_ req: BrowserRequest) -> some View {
        Button {
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
