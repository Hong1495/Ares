import SwiftUI
import UniformTypeIdentifiers

struct LogsView: View {
    @EnvironmentObject var clashViewModel: ClashViewModel
    @AppStorage("logLevel") private var globalLogLevel: String = "info"
    @State private var selectedTabLevel: String = "all"
    @State private var searchText = ""
    @State private var autoScroll = true

    var filteredLogs: [String] {
        let lines = clashViewModel.logs
        var filtered = lines

        // 1. Mandatory Baseline: Filter by Global Log Level (from Settings)
        let globalPriority = priority(for: globalLogLevel)
        filtered = filtered.filter { priority(forLine: $0) >= globalPriority }

        // 2. View Filter: Tab-specific logic
        if selectedTabLevel == "all" {
            // "All" keeps everything from the global baseline
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
            LogsTools(level: $selectedTabLevel, search: $searchText, autoScroll: $autoScroll,
                      canClear: !clashViewModel.logs.isEmpty, canExport: !filteredLogs.isEmpty,
                      onClear: { clashViewModel.clearLogs() }, onExport: exportLogs)
            Divider()
            LogsSurface(lines: filteredLogs, autoScroll: autoScroll,
                        emptyTitle: emptyLogsTitle, emptyDescription: emptyLogsDescription)
        }
        .background(DS.canvas)
        .navigationTitle("")
        .toolbar {
            CollectionTitleToolbar(title: "Logs", count: filteredLogs.count, unit: "Lines")
        }
    }

    private var emptyLogsTitle: String {
        clashViewModel.logs.isEmpty ? "No logs yet" : "No matching logs"
    }

    private var emptyLogsDescription: String {
        clashViewModel.logs.isEmpty ? "Core and application events will appear here." : "Change the level or search filter to show logs."
    }

    private func exportLogs() {
        let panel = NSSavePanel()
        let lines = filteredLogs
        panel.nameFieldStringValue = "ares-logs-\(Date().ISO8601Format()).txt"
        panel.allowedContentTypes = [.plainText]

        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    AppState.shared.reportError("Could not export logs: \(error.localizedDescription)")
                }
            }
        }
    }
}
