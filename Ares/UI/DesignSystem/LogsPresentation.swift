import SwiftUI

struct LogsTools: View {
    @Binding var level: String
    @Binding var search: String
    @Binding var autoScroll: Bool
    let canClear: Bool
    let canExport: Bool
    let onClear: () -> Void
    let onExport: () -> Void

    var body: some View {
        HStack(spacing: DS.Space.md) {
            Picker("Log level", selection: $level) {
                Text("All").tag("all")
                Text("Debug").tag("debug")
                Text("Info").tag("info")
                Text("Warning").tag("warning")
                Text("Error").tag("error")
            }
            .labelsHidden().pickerStyle(.segmented).controlSize(.small)
            .frame(minWidth: 240, idealWidth: 300, maxWidth: 320)
            Spacer(minLength: DS.Space.sm)
            TextField("Search logs", text: $search)
                .textFieldStyle(.roundedBorder).controlSize(.small)
                .frame(minWidth: 130, idealWidth: 200, maxWidth: 200)
            HStack(spacing: DS.Space.xs) {
                Toggle(isOn: $autoScroll) {
                    Image(systemName: "arrow.down.to.line").frame(width: 16, height: 16)
                }
                .toggleStyle(.button)
                .tint(DS.accent)
                .help(autoScroll ? "Auto-scroll on · Click to stop following" : "Auto-scroll off · Click to follow latest logs")
                .accessibilityLabel("Auto-scroll")
                Button(action: onClear) { Image(systemName: "trash").frame(width: 16, height: 16) }
                    .help("Clear all logs").accessibilityLabel("Clear all logs").disabled(!canClear)
                Button(action: onExport) { Image(systemName: "square.and.arrow.up").frame(width: 16, height: 16) }
                    .help("Export matching logs").accessibilityLabel("Export matching logs").disabled(!canExport)
            }
            .font(.system(size: 13, weight: .regular)).buttonStyle(.borderless)
        }
        .padding(.horizontal, DS.Space.lg)
        .padding(.top, DS.Space.pageTop)
        .padding(.bottom, DS.Space.md)
    }
}

struct LogsSurface: View {
    let lines: [String]
    let autoScroll: Bool
    let emptyTitle: String
    let emptyDescription: String

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if lines.isEmpty {
                    ContentUnavailableView(emptyTitle, systemImage: "text.alignleft", description: Text(emptyDescription))
                        .frame(maxWidth: .infinity, minHeight: 260)
                } else {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                            LogLineView(line: line, index: index)
                        }
                        Color.clear.frame(height: 1).id("latest-log")
                    }.padding(DS.Space.lg)
                }
            }
            .onAppear { if autoScroll { proxy.scrollTo("latest-log", anchor: .bottom) } }
            // The ring buffer can receive new entries without changing its count.
            .onChange(of: lines) { _, _ in
                if autoScroll { proxy.scrollTo("latest-log", anchor: .bottom) }
            }
            .onChange(of: autoScroll) { _, follow in
                if follow { proxy.scrollTo("latest-log", anchor: .bottom) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
