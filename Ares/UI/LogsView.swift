import SwiftUI
import UniformTypeIdentifiers

struct LogsView: View {
    @EnvironmentObject var clashViewModel: ClashViewModel
    @AppStorage("logLevel") private var globalLogLevel: String = "info"
    @State private var selectedTabLevel: String = "all"
    @State private var searchText = ""
    @State private var autoScroll = true
    
    // Levels mapped for Priority Filtering
    private let levels = ["debug", "info", "warning", "error", "silent"]
    
    var filteredLogs: [String] {
        let lines = clashViewModel.logs
        var filtered = lines
        
        // 1. Mandatory Baseline: Filter by Global Log Level (from Settings)
        let globalPriority = priority(for: globalLogLevel)
        filtered = filtered.filter { priority(forLine: $0) >= globalPriority }
        
        // 2. View Filter: Tab-specific logic
        if selectedTabLevel == "all" {
            // "All" keeps everything from the global baseline
        } else if selectedTabLevel == "silent" {
            return []
        } else {
            // Specific tabs: Strictly literal matching for that exact level
            let targetPriority = priority(for: selectedTabLevel)
            filtered = filtered.filter { priority(forLine: $0) == targetPriority }
        }
        
        // Filter by search
        if !searchText.isEmpty {
            filtered = filtered.filter { line in
                line.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return filtered
    }
    
    private func priority(for level: String) -> Int {
        switch level {
        case "debug": return 0
        case "info": return 1
        case "warning": return 2
        case "error": return 3
        case "silent": return 999
        default: return -1
        }
    }
    
    private func priority(forLine line: String) -> Int {
        let lower = line.lowercased()
        if lower.contains("error") || lower.contains("fatal") || lower.contains("31m") {
            return 3
        } else if lower.contains("warning") || lower.contains("warn") || lower.contains("33m") {
            return 2
        } else if lower.contains("debug") || lower.contains("35m") {
            return 0
        } else if lower.contains("info") || lower.contains("36m") {
            return 1
        } else {
            // Default to Info for our own apps logs [timestamp]
            return 1
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 12) {
                // Level filter
                HStack(spacing: 6) {
                    Text("Level:")
                        .font(.footnote)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    
                    Picker("", selection: $selectedTabLevel) {
                        Text("All").tag("all")
                        Text("Debug").tag("debug")
                        Text("Info").tag("info")
                        Text("Warning").tag("warning")
                        Text("Error").tag("error")
                        Text("Silent").tag("silent")
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 400)
                }
                
                Spacer()
                
                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search logs...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(6)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
                .frame(width: 200)
                
                // Auto-scroll toggle
                Toggle("Auto-scroll", isOn: $autoScroll)
                    .toggleStyle(.switch)
                
                Text("\(filteredLogs.count)")
                    .font(.footnote)
                    .fontWeight(.medium)
                    .monospacedDigit()
                
                // Clear button
                Button {
                    clashViewModel.clearLogs()
                } label: {
                    Image(systemName: "trash")
                }
                .help("Clear logs")
                
                // Export button
                Button {
                    exportLogs()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .help("Export logs")
            }
            .padding()
            
            Divider()
            
            // Logs display
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(filteredLogs.enumerated()), id: \.offset) { index, line in
                            LogLineView(line: line, index: index)
                                .id(index)
                        }
                    }
                    .padding(8)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .onChange(of: filteredLogs.count) { oldValue, newValue in
                    if autoScroll, let lastIndex = filteredLogs.indices.last {
                        withAnimation {
                            proxy.scrollTo(lastIndex, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Logs")
    }
    
    private func exportLogs() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "clash-logs-\(Date().ISO8601Format()).txt"
        panel.allowedContentTypes = [.plainText]
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? clashViewModel.logs.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}

struct LogLineView: View {
    let line: String
    let index: Int
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Line number
            Text("\(index + 1)")
                .font(.system(.footnote, design: .monospaced))
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .trailing)
            
            // Log content
            Text(line)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(lineColor)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
        .background(index % 2 == 0 ? Color.clear : Color.gray.opacity(0.05))
    }
    
    private var lineColor: Color {
        let lower = line.lowercased()
        if lower.contains("error") || lower.contains("fatal") {
            return .red
        } else if lower.contains("warning") || lower.contains("warn") {
            return .orange
        } else if lower.contains("debug") {
            return .purple
        } else {
            return .primary
        }
    }
}
