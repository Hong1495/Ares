import SwiftUI
import SubscriptionKit

struct PolicyGroupsView: View {
    var embedded = false
    @EnvironmentObject private var controller: ClashController
    @Environment(\.dismiss) private var dismiss
    @State private var snapshot: PolicyGroupService.Snapshot?
    @State private var selection: String?
    @State private var search = ""
    @State private var error: String?
    @State private var editing: PolicyConfiguration.Group?
    @State private var busy = false
    private struct CompositionRequest: Identifiable {
        let id = UUID()
        let recommended: Bool
    }
    @State private var composition: CompositionRequest?
    @State private var liveGroups: [ProxyGroup] = []
    @State private var graph: PolicyGraph.Snapshot?
    @State private var capturedAt: Date?
    private var selected: PolicyConfiguration.Group? { snapshot?.effective.first { $0.name == selection } }
    var body: some View {
        VStack(spacing: 0) {
            if !embedded { HStack {
                Text("Policy Groups").font(DS.Typography.secondary.weight(.semibold)).fixedSize()
                Spacer()
                Button("Done") { dismiss() }.controlSize(.small).fixedSize()
            }.padding(DS.Space.lg) }
            CollectionTools(placeholder: "Search groups", search: $search) {
                Button { composition = .init(recommended: false) } label: { Label("Compose", systemImage: "square.and.pencil") }
                    .disabled(snapshot == nil || busy).help("Compose policies and routing rules").accessibilityLabel("Compose policies")
                Button("Recommended…") { composition = .init(recommended: true) }
                    .disabled(snapshot == nil || busy).help("Review recommended groups before applying")
                Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(busy).help("Read policy groups").accessibilityLabel("Read policy groups")
            }
            if let error { Text(error).font(DS.Typography.metadata).foregroundStyle(Color.statusBad).padding(DS.Space.md) }
            Divider()
            Table((snapshot?.effective ?? []).filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }, selection: $selection) {
                TableColumn("Group") { Text($0.name).font(DS.Typography.metadata).lineLimit(1).truncationMode(.middle).help($0.name) }
                TableColumn("Type") { Text($0.type).font(DS.Typography.metadata).foregroundStyle(.secondary) }.width(100)
                TableColumn("Resources") { Text($0.providers.joined(separator: ", ")).font(DS.Typography.metadata).lineLimit(1).help($0.providers.joined(separator: ", ")) }
                TableColumn("") { group in
                    Button { editing = group } label: { Image(systemName: "slider.horizontal.3") }
                        .buttonStyle(.borderless).disabled(PolicyConfiguration.editableFields(type: group.type).isEmpty)
                        .help("Edit local parameters").accessibilityLabel("Edit \(group.name)")
                }.width(30)
            }.frame(minHeight: 150)
            if let selected {
                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    Text(selected.name).font(DS.Typography.secondary.weight(.medium)).lineLimit(1).truncationMode(.middle)
                    if let live = liveGroups.first(where: { $0.name == selected.name }) {
                        Text(live.type == "LoadBalance" ? "Load balancing chooses an exit per connection." : "Current: " + (live.now ?? "—") + " · " + (live.supportsAutomaticSelection ? (live.manualSelection == nil ? "Automatic" : "Pinned") : "Manual"))
                            .font(DS.Typography.metadata).foregroundStyle(.secondary)
                    }
                    let members = graph?.edges.filter { $0.parent == selected.name } ?? []
                    if graph != nil {
                        Table(members) {
                            TableColumn("Runtime member") { Text($0.member).font(DS.Typography.metadata).lineLimit(1).help($0.member) }
                            TableColumn("Kind") { Text($0.kind).font(DS.Typography.metadata) }.width(90)
                            TableColumn("Current") { Text($0.active ? "✓" : "—").font(DS.Typography.metadata) }.width(60)
                        }.frame(minHeight: 130)
                    } else {
                        Text("Configured members: " + selected.members.joined(separator: ", ")).font(DS.Typography.metadata).textSelection(.enabled)
                    }
                }.padding(DS.Space.md)
            }
            if let graph, !graph.issues.isEmpty {
                ScrollView { VStack(alignment: .leading) { ForEach(graph.issues, id: \.self) { Text($0) } } }
                    .font(DS.Typography.metadata).foregroundStyle(Color.statusWarn).frame(maxHeight: 70).padding(.horizontal, DS.Space.lg)
            }
            Text(capturedAt.map { "Runtime snapshot: " + $0.formatted(date: .omitted, time: .standard) + " · Membership is not a physical network route." } ?? "Saved subscription · Runtime membership is unavailable.")
                .font(DS.Typography.metadata).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(DS.Space.lg)
        }.frame(minWidth: embedded ? 0 : 800, minHeight: 500).background(DS.canvas)
        .scrollIndicators(.never, axes: [.horizontal, .vertical])
        .toolbar { if embedded { CollectionTitleToolbar(title: "Policies", count: snapshot?.effective.count, unit: "Groups") } }
        .task { await load() }
        .sheet(item: $composition, onDismiss: { Task { await load() } }) { request in
            if let snapshot { PolicyCompositionView(snapshot: snapshot, startWithRecommended: request.recommended) }
        }
        .sheet(item: $editing, onDismiss: { Task { await load() } }) { group in
            if let snapshot { PolicyParameterEditor(group: group, snapshot: snapshot) }
        }
        .onChange(of: controller.runtimeGeneration) { _, _ in graph = nil; liveGroups = []; capturedAt = nil }
    }
    @MainActor private func load() async {
        guard !busy else { return }
        busy = true; error = nil; graph = nil; capturedAt = nil; liveGroups = []
        defer { busy = false }
        do { snapshot = try await PolicyGroupService.load() }
        catch { snapshot = nil; self.error = "Policy configuration could not be read. Refresh after the current operation finishes."; return }
        // Saved groups remain usable offline; only a matching running profile supplies live edges.
        guard PolicyGroupService.canReadRuntime else { return }
        let generation = controller.runtimeGeneration
        do {
            try await controller.fetchProxiesData()
            guard generation == controller.runtimeGeneration, PolicyGroupService.canReadRuntime else { throw CancellationError() }
            liveGroups = controller.proxyGroups
            graph = PolicyGraph.inspect(groups: liveGroups, nodes: controller.proxyNodes); capturedAt = Date()
        } catch { self.error = "Saved configuration loaded; runtime membership could not be verified." }
    }
}

private struct PolicyParameterEditor: View {
    let group: PolicyConfiguration.Group
    let snapshot: PolicyGroupService.Snapshot
    @Environment(\.dismiss) private var dismiss
    @State private var enabled = Set<String>()
    @State private var values: [String: String] = [:]
    @State private var edits: [String: [String: String]] = [:]
    @State private var error: String?
    @State private var applying = false
    private var inherited: PolicyConfiguration.Group? { snapshot.inherited.first { $0.name == group.name } }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(group.name).font(DS.Typography.secondary.weight(.semibold)).lineLimit(1).truncationMode(.middle).help(group.name)
                Spacer()
                Button("Cancel") { dismiss() }.fixedSize()
                Button("Apply") { apply() }.buttonStyle(.borderedProminent).fixedSize()
            }.controlSize(.small).padding(DS.Space.lg).disabled(applying)
            Form {
                ForEach(PolicyConfiguration.editableFields(type: group.type), id: \.self) { field in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Toggle(field, isOn: Binding(get: { enabled.contains(field) }, set: { if $0 { enabled.insert(field) } else { enabled.remove(field) } }))
                                .toggleStyle(.checkbox).fixedSize()
                            Spacer()
                            if field == "lazy" {
                                Picker("Lazy", selection: valueBinding(field)) {
                                    Text("Not set").tag("")
                                    Text("Enabled").tag("true")
                                    Text("Disabled").tag("false")
                                }.labelsHidden().disabled(!enabled.contains(field)).frame(width: 180)
                            } else if field == "strategy" {
                                Picker("Strategy", selection: valueBinding(field)) {
                                    Text("Not set").tag("")
                                    Text("Consistent hashing").tag("consistent-hashing")
                                    Text("Round robin").tag("round-robin")
                                    Text("Sticky sessions").tag("sticky-sessions")
                                }.labelsHidden().disabled(!enabled.contains(field)).frame(width: 180)
                            } else {
                                TextField(inherited?.fields[field] ?? "Core default", text: valueBinding(field))
                                    .labelsHidden().accessibilityLabel(field).disabled(!enabled.contains(field))
                                    .frame(minWidth: 100, idealWidth: 220, maxWidth: 270)
                            }
                        }
                        Text(enabled.contains(field) ? "Local override" : "Inherited: " + (inherited?.fields[field] ?? "Core default"))
                            .font(DS.Typography.metadata).foregroundStyle(.secondary)
                    }
                }
            }.formStyle(.grouped).disabled(applying)
            if let error { Text(error).font(DS.Typography.metadata).foregroundStyle(Color.statusBad).padding(DS.Space.md) }
            Text("Unchecked fields inherit from the subscription. Interval is in seconds; timeout and tolerance are in milliseconds.")
                .font(DS.Typography.metadata).foregroundStyle(.secondary).padding(DS.Space.lg)
        }.frame(width: 620, height: 520).background(DS.canvas).interactiveDismissDisabled(applying)
        .onAppear {
            do {
                edits = try PolicyConfiguration.decodeOverrides(snapshot.stored)
                enabled = Set((edits[group.name] ?? [:]).keys.filter { PolicyConfiguration.fields.contains($0) })
                values = group.fields
            } catch { self.error = "Saved overrides could not be read." }
        }
    }
    private func valueBinding(_ field: String) -> Binding<String> {
        Binding(get: { enabled.contains(field) ? values[field] ?? "" : inherited?.fields[field] ?? "" },
                set: { values[field] = $0 })
    }
    private func apply() {
        do {
            var updated = (edits[group.name] ?? [:]).filter { PolicyConfiguration.structuralFields.contains($0.key) }
            for field in enabled where PolicyConfiguration.fields.contains(field) { updated[field] = values[field] ?? "" }
            edits[group.name] = updated
            if edits[group.name]?.isEmpty == true { edits.removeValue(forKey: group.name) }
            let text = try PolicyConfiguration.encodeOverrides(edits)
            applying = true; error = nil
            Task { @MainActor in
                if await PolicyGroupService.apply(text, snapshot: snapshot) { dismiss() }
                else { error = AppState.shared.lastOperationError ?? "Another operation is in progress." }
                applying = false
            }
        } catch { self.error = "Policy parameters could not be encoded." }
    }
}
