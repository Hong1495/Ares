import SwiftUI

/// Read-only history; opening it never repeats a resource request.
struct ResourceActivityView: View {
    @EnvironmentObject private var controller: ClashController
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var activity = ResourceActivity.shared
    @State private var selection: UUID?
    @State private var search = ""
    var kind: ResourceActivity.Kind? = nil
    var name: String? = nil
    private var entries: [ResourceActivity.Entry] {
        activity.entries.filter { (kind == nil || $0.kind == kind) && (name == nil || $0.name == name) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Resource Activity").font(DS.Typography.secondary.weight(.semibold)).fixedSize()
                Spacer()
                Button("Done") { dismiss() }.controlSize(.small)
            }.padding(DS.Space.lg)
            CollectionTools(placeholder: "Search resources", search: $search) { EmptyView() }
            Divider()
            Table(entries, selection: $selection) {
                TableColumn("Resource") { Text($0.name).lineLimit(1).truncationMode(.middle).help($0.name) }
                TableColumn("Type") { Text($0.kind.rawValue) }.width(50)
                TableColumn("Action") { Text($0.action.rawValue) }.width(85)
                TableColumn("Result") { entry in
                    Text(entry.outcome.rawValue).foregroundStyle(selection == entry.id ? Color(nsColor: .selectedControlTextColor) : (entry.outcome == .failed ? Color.statusWarn : Color.primary))
                }.width(95)
                TableColumn("Runtime") { entry in
                    Text(entry.generation == controller.runtimeGeneration && entry.endpoint == controller.baseURL ? "Current" : "Previous")
                        .foregroundStyle(.secondary)
                }.width(65)
                TableColumn("Started") { Text($0.startedAt, style: .time).monospacedDigit() }.width(95)
            }.font(DS.Typography.metadata)
            if let entry = entries.first(where: { $0.id == selection }) {
                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    Text(entry.action.rawValue + " · " + entry.phase.rawValue).font(DS.Typography.secondary)
                    Text(entry.detail).textSelection(.enabled)
                    if let finished = entry.finishedAt { Text("Finished: " + finished.formatted(date: .omitted, time: .standard)).foregroundStyle(.secondary) }
                }.font(DS.Typography.metadata).frame(maxWidth: .infinity, alignment: .leading).padding(DS.Space.lg)
            }
            Text(entries.isEmpty ? "No resource operations recorded in this app session." : "App-initiated operations in this session. Core-scheduled updates are not reported by this history.")
                .font(DS.Typography.metadata).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(DS.Space.lg)
        }.frame(minWidth: 800, minHeight: 460).background(DS.canvas)
    }
}
