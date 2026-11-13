import SwiftUI

struct SettingsTabs: View {
    let titles: [String]
    @Binding var selection: Int

    var body: some View {
        Picker("Settings category", selection: $selection) {
            ForEach(titles.indices, id: \.self) { index in
                Text(titles[index]).tag(index)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .fixedSize()
        .frame(maxWidth: 520, alignment: .leading)
    }
}

struct SettingsSectionTitle: View {
    let title: String
    let icon: String
    init(_ title: String, icon: String) { self.title = title; self.icon = icon }
    var body: some View {
        Label(title, systemImage: icon)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.bottom, 4)
    }
}

struct SettingsRowStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 16) {
            configuration.label.font(.system(size: 13))
            Spacer(minLength: 16)
            configuration.content.controlSize(.small)
        }
        .frame(minHeight: 28)
        .frame(maxWidth: .infinity)
    }
}

/// Compact ownership action shared with the inert design preview.
struct SettingsSourceControl: View {
    let source: String
    let isLocal: Bool
    let pending: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(source + (pending ? " · Pending" : ""))
                .foregroundStyle(.secondary)
            Button(action: action) {
                Image(systemName: isLocal ? "arrow.uturn.backward" : "pencil")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .accessibilityLabel(isLocal ? "Restore inheritance" : "Use local override")
            .help(isLocal ? "Restore inheritance after Apply Changes" : "Use a local override")
        }.font(.system(size: 11))
    }
}

struct SettingsRuntimeRow: Identifiable {
    let id: String
    let saved: String
    let running: String
    let result: String
    let differs: Bool
}

/// Shared read-only table; no service or network dependency.
struct SettingsRuntimeTable: View {
    let rows: [SettingsRuntimeRow]
    var body: some View {
        Table(rows) {
            TableColumn("Field") { Text($0.id).font(.system(size: 12, design: .monospaced)) }
                .width(min: 130, ideal: 175)
            TableColumn("Saved") { Text($0.saved).textSelection(.enabled) }
            TableColumn("Running") { Text($0.running).textSelection(.enabled) }
            TableColumn("Result") { row in
                Text(row.result).foregroundStyle(row.differs ? Color.orange : Color.secondary)
            }.width(100)
        }
    }
}
