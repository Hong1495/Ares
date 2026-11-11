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
        VStack(spacing: DS.Space.md) {
            DSCard(padding: DS.Space.md) {
                toolbarRow
            }

            logSurface
        }
        .padding(DS.Space.lg)
        .background(DS.canvas)
        .navigationTitle("Logs")
    }

    // MARK: - Toolbar

    private var toolbarRow: some View {
        HStack(spacing: DS.Space.md) {
            // Level filter
            Picker("", selection: $selectedTabLevel) {
                Text("All").tag("all")
                Text("Debug").tag("debug")
                Text("Info").tag("info")
                Text("Warning").tag("warning")
                Text("Error").tag("error")
                Text("Silent").tag("silent")
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.small)
            .frame(maxWidth: 320)

            Spacer(minLength: DS.Space.sm)

            // Search
            TextField("Search logs", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .frame(minWidth: 120, idealWidth: 180, maxWidth: 180)

            // Match count
            Text("\(filteredLogs.count)")
                .font(DS.Typography.metadata.monospaced().weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .help("Matching lines")

            // Auto-scroll toggle
            Toggle("Auto-scroll", isOn: $autoScroll)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(DS.Typography.metadata)
                .fixedSize()

            // Clear / Export
            HStack(spacing: DS.Space.xs) {
                Button {
                    clashViewModel.clearLogs()
                } label: {
                    Image(systemName: "trash")
                        .font(DS.Typography.secondary.weight(.medium))
                }
                .buttonStyle(.borderless)
                .help("Clear logs")

                Button {
                    exportLogs()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(DS.Typography.secondary.weight(.medium))
                }
                .buttonStyle(.borderless)
                .help("Export logs")
            }
        }
    }

    // MARK: - Log surface

    private var logSurface: some View {
        DSCard(padding: 0, spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    if filteredLogs.isEmpty {
                        ContentUnavailableView {
                            Label(emptyLogsTitle, systemImage: "text.line.first.and.arrowtriangle.forward")
                        } description: {
                            Text(emptyLogsDescription)
                        }
                        .frame(maxWidth: .infinity, minHeight: 260)
                    } else {
                        LazyVStack(alignment: .leading, spacing: DS.Space.xxs) {
                            ForEach(Array(filteredLogs.enumerated()), id: \.offset) { index, line in
                                LogLineView(line: line, index: index)
                                    .id(index)
                            }
                        }
                        .padding(DS.Space.md)
                    }
                }
                .onChange(of: filteredLogs.count) { oldValue, newValue in
                    if autoScroll, let lastIndex = filteredLogs.indices.last {
                        withAnimation {
                            proxy.scrollTo(lastIndex, anchor: .bottom)
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyLogsTitle: String {
        clashViewModel.logs.isEmpty ? "No logs yet" : "No matching logs"
    }

    private var emptyLogsDescription: String {
        clashViewModel.logs.isEmpty ? "Core and application events will appear here." : "Change the level or search filter to show logs."
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

// MARK: - Severity

/// Visual severity for a log line. Color is used for the marker only —
/// the line text itself stays primary/secondary ink.
private enum LogSeverity {
    case debug
    case info
    case warning
    case error

    init(line: String) {
        let lower = line.lowercased()
        if lower.contains("error") || lower.contains("fatal") || lower.contains("31m") {
            self = .error
        } else if lower.contains("warning") || lower.contains("warn") || lower.contains("33m") {
            self = .warning
        } else if lower.contains("debug") || lower.contains("35m") {
            self = .debug
        } else {
            self = .info
        }
    }

    var marker: AnyShapeStyle {
        switch self {
        case .error: return AnyShapeStyle(Color.statusBad)
        case .warning: return AnyShapeStyle(Color.statusWarn)
        case .debug: return AnyShapeStyle(HierarchicalShapeStyle.tertiary)
        case .info: return AnyShapeStyle(HierarchicalShapeStyle.secondary)
        }
    }

    var ink: Color {
        switch self {
        case .debug: return .secondary
        default: return .primary
        }
    }
}

struct LogLineView: View {
    let line: String
    let index: Int

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.sm) {
            // Severity marker
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(severity.marker)
                .frame(width: 3, height: 12)
                .padding(.top, 2.5)

            // Line number
            Text("\(index + 1)")
                .font(DS.Typography.metadata.monospaced())
                .foregroundStyle(.tertiary)
                .frame(width: 34, alignment: .trailing)

            // Log content
            Text(line)
                .font(DS.Typography.metadata.monospaced())
                .foregroundStyle(severity.ink)
                .lineSpacing(1.5)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 1)
    }

    private var severity: LogSeverity {
        LogSeverity(line: line)
    }
}
