import SwiftUI
import UniformTypeIdentifiers

struct LogsView: View {
    @EnvironmentObject var clashViewModel: ClashViewModel
    @State private var selectedLevel: LogLevel = .all
    @State private var searchText = ""
    @State private var autoScroll = true
    
    enum LogLevel: String, CaseIterable {
        case all = "All"
        case error = "Error"
        case warning = "Warning"
        case info = "Info"
        case debug = "Debug"
    }
    
    var filteredLogs: [String] {
        // Direct access, no costly splitting
        let lines = clashViewModel.logs
        
        var filtered = lines // .filter { !$0.isEmpty } // Already non-empty
        
        // Filter out Clash core INFO logs (too noisy)
        filtered = filtered.filter { line in
            // Keep our own logs (starts with timestamp in brackets)
            if line.hasPrefix("[") {
                return true
            }
            // Filter out Clash INFO logs
            if line.contains("INFO") || line.contains("36m") {
                return false
            }
            // Keep ERROR and WARN
            return true
        }
        
        // Filter by level
        if selectedLevel != .all {
            filtered = filtered.filter { line in
                line.localizedCaseInsensitiveContains(selectedLevel.rawValue)
            }
        }
        
        // Filter by search
        if !searchText.isEmpty {
            filtered = filtered.filter { line in
                line.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return filtered
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 12) {
                // Level filter
                HStack(spacing: 6) {
                    Text("Level:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Picker("", selection: $selectedLevel) {
                        ForEach(LogLevel.allCases, id: \.self) { level in
                            Text(level.rawValue).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 350)
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
                    .font(.caption)
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
                ScrollView {
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
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .trailing)
            
            // Log content
            Text(line)
                .font(.system(.caption, design: .monospaced))
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
