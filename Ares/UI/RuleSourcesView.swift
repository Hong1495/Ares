import SwiftUI
import SubscriptionKit

struct RuleSourcesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var document: RuleSourceDocument.Document?
    @State private var error: String?
    @State private var search = ""
    @State private var busy = false
    @State private var capturedAt: Date?
    @State private var selection: String?
    let provider: String?
    init(provider: String? = nil) { self.provider = provider }
    private var rows: [RuleSourceDocument.Row] {
        let rows = provider.map { document?.references(to: $0) ?? [] } ?? document?.rows ?? []
        return rows.filter { search.isEmpty || $0.rule.localizedCaseInsensitiveContains(search) || $0.location.localizedCaseInsensitiveContains(search) || $0.origin.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(provider ?? "Rule Sources").font(DS.Typography.secondary.weight(.semibold))
                    .lineLimit(1).truncationMode(.middle).help(provider ?? "Rule Sources")
                Spacer()
                Button("Done") { dismiss() }.controlSize(.small).fixedSize()
            }.padding(DS.Space.lg)
            CollectionTools(placeholder: "Search source rules", search: $search) {
                Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(busy).help("Read verified rule sources").accessibilityLabel("Read verified rule sources")
            }
            Divider()
            if let error { Text(error).font(DS.Typography.metadata).foregroundStyle(Color.statusBad).padding(DS.Space.md) }
            Table(rows, selection: $selection) {
                TableColumn("Location") { Text($0.location).font(DS.Typography.metadata.monospaced()).lineLimit(1).help($0.location) }.width(min: 120, ideal: 180, max: 240)
                TableColumn("Source") { Text($0.origin).font(DS.Typography.metadata).foregroundStyle(.secondary) }.width(145)
                TableColumn("Rule") { Text($0.rule).font(DS.Typography.metadata.monospaced()).lineLimit(1).truncationMode(.middle).help($0.rule) }
            }
            if let row = rows.first(where: { $0.id == selection }) {
                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    Text(row.rule).font(DS.Typography.metadata.monospaced()).textSelection(.enabled)
                    if !row.providers.isEmpty { Text("Rule sets: " + row.providers.joined(separator: ", ")) }
                    if !row.subRules.isEmpty { Text("Sub-rules: " + row.subRules.joined(separator: ", ")) }
                }.font(DS.Typography.metadata).frame(maxWidth: .infinity, alignment: .leading).padding(DS.Space.lg)
            }
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                if let capturedAt { Text("Snapshot: " + capturedAt.formatted(date: .abbreviated, time: .standard)) }
                Text("Verified configuration · includes nested expressions and sub-rule sections. This view does not report runtime hits.")
                if let issues = document?.issues, !issues.isEmpty {
                    ScrollView { VStack(alignment: .leading) { ForEach(issues, id: \.self) { Text($0) } } }.frame(maxHeight: 65)
                }
            }.font(DS.Typography.metadata).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(DS.Space.lg)
        }.frame(minWidth: 820, minHeight: 500).background(DS.canvas)
        .task { await load() }
    }
    @MainActor private func load() async {
        guard !busy else { return }
        busy = true; error = nil; document = nil; selection = nil; capturedAt = nil
        defer { busy = false }
        do { document = try await RuleSourceService.load(); capturedAt = Date() }
        catch { self.error = "Verified rule sources are unavailable. Wait for a stable running core, then refresh." }
    }
}
