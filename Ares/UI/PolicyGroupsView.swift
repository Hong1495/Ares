import SwiftUI
import Combine
import SubscriptionKit

struct PolicyGroupsView: View {
    var embedded = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var profiles = ProfileService.shared
    @ObservedObject private var controller = ClashController.shared
    @EnvironmentObject private var core: ClashViewModel
    @StateObject private var model = PolicyGroupsViewModel()
    @State private var search = ""
    @State private var detail = 0
    @State private var editor: EditorRequest?
    @State private var composition: CompositionRequest?
    @State private var removal: RemovalRequest?
    @State private var applying = false
    @State private var actionError: String?
    private struct EditorRequest: Identifiable { let id: String; let isNew: Bool; let snapshot: PolicyGroupService.Snapshot }
    private struct CompositionRequest: Identifiable { let id = UUID(); let recommended: Bool; let snapshot: PolicyGroupService.Snapshot }
    private struct RemovalRequest: Identifiable { let id: String; let restore: Bool; let snapshot: PolicyGroupService.Snapshot }
    private var isEditing: Bool { editor != nil || composition != nil || removal != nil || applying }
    private var rows: [PolicyConfiguration.Group] {
        (model.snapshot?.effective ?? []).filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.type.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        VStack(spacing: 0) {
            if !embedded {
                HStack { Text("Policies").font(DS.Typography.secondary.weight(.semibold)); Spacer(); Button("Done") { dismiss() } }
                    .controlSize(.small).padding(DS.Space.lg)
            }
            CollectionTools(placeholder: "Search groups", search: $search) {
                WorkspaceAction(title: "New Group…", symbol: "plus", primary: true) {
                    if let snapshot = model.snapshot { editor = .init(id: "", isNew: true, snapshot: snapshot) }
                }
                    .disabled(model.snapshot == nil).help("Create policy group").accessibilityLabel("Create policy group")
                WorkspaceAction(title: "Edit…", symbol: "pencil") { editSelected() }
                    .disabled(model.selected == nil || !PolicyConfiguration.types.contains(model.selected?.type ?? ""))
                    .help("Edit behavior, members and resources").accessibilityLabel("Edit selected policy group")
                WorkspaceAction(title: "Compose…", symbol: "square.stack") { compose(false) }
                    .disabled(model.snapshot == nil).help("Compose groups and rules")
                Menu {
                    Button("Add Recommended…") { compose(true) }
                    Divider()
                    Button("Delete Group…", role: .destructive) {
                        if let group = model.selected, let snapshot = model.snapshot { removal = .init(id: group.name, restore: false, snapshot: snapshot) }
                    }.disabled(model.selected == nil)
                    Button("Restore Inheritance…") {
                        if let group = model.selected, let snapshot = model.snapshot { removal = .init(id: group.name, restore: true, snapshot: snapshot) }
                    }.disabled(!hasOverride)
                    if let snapshot = model.snapshot {
                        let removed = ((try? PolicyConfiguration.decodeOverrides(snapshot.stored)) ?? [:]).filter { $0.value["_delete"] == "true" }.keys.sorted()
                        if !removed.isEmpty {
                            Menu("Restore Removed Group") {
                                ForEach(removed, id: \.self) { name in
                                    Button(name) { removal = .init(id: name, restore: true, snapshot: snapshot) }
                                }
                            }
                        }
                    }
                } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .disabled(model.snapshot == nil).help("Policy actions").accessibilityLabel("Policy actions")
                Button { Task { await model.reload() } } label: { Image(systemName: "arrow.clockwise") }
                    .help("Reload saved groups and runtime").accessibilityLabel("Reload policies")
            }.disabled(model.busy || applying)
            DSCard(padding: 0, spacing: 0) {
                policyTable
                if let group = model.selected { Divider(); details(group) }
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .padding(.horizontal, DS.Space.lg).padding(.bottom, DS.Space.lg)
            if let error = actionError ?? model.error {
                Text(error).font(DS.Typography.metadata).foregroundStyle(Color.statusBad)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, DS.Space.lg).padding(.bottom, DS.Space.md)
            } else if let message = model.message {
                Text(message).font(DS.Typography.metadata).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, DS.Space.lg).padding(.bottom, DS.Space.md)
            }
        }
        .background(DS.canvas).font(DS.Typography.secondary)
        .frame(minWidth: embedded ? 0 : 680, minHeight: embedded ? 0 : 540)
        .scrollIndicators(.never, axes: [.horizontal, .vertical])
        .toolbar { if embedded { CollectionTitleToolbar(title: "Policies", count: model.snapshot?.effective.count, unit: "Groups") } }
        .task {
            await model.reload()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(10)) } catch { break }
                if scenePhase == .active, !isEditing { await model.reload() }
            }
        }
        .onChange(of: profiles.activeProfileRevision) { _, _ in
            model.invalidate(profileChanged: true)
            Task { await model.reload() }
        }
        .onChange(of: controller.runtimeGeneration) { _, _ in refreshRuntime() }
        .onChange(of: core.isToggling) { _, _ in refreshRuntime() }
        .onChange(of: core.appliedProfileRevision) { _, _ in refreshRuntime() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, !isEditing { refresh() }
        }
        .onChange(of: search) { _, _ in
            if let selection = model.selection, !rows.contains(where: { $0.name == selection }) { model.selection = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).debounce(for: .milliseconds(400), scheduler: RunLoop.main)) { _ in
            if !isEditing { Task { await model.reload() } }
        }
        .sheet(item: $editor, onDismiss: refresh) { request in
            let catalog = try? PolicyConfiguration.catalog(request.snapshot.source)
            PolicyStructureEditor(name: request.id, isNew: request.isNew,
                group: request.snapshot.effective.first { $0.name == request.id }, inherited: request.snapshot.inherited.first { $0.name == request.id },
                override: ((try? PolicyConfiguration.decodeOverrides(request.snapshot.stored)) ?? [:])[request.id] ?? [:],
                targets: Array(Set((catalog?.nodes ?? []) + request.snapshot.effective.map(\.name) + ["DIRECT", "REJECT", "REJECT-DROP", "PASS"])).filter { $0 != request.id }.sorted(),
                providers: catalog?.providers ?? [], allowsNaming: request.id.isEmpty, saveTitle: "Apply") { name, fields in
                    do {
                        var edits = try PolicyConfiguration.decodeOverrides(request.snapshot.stored)
                        if request.id.isEmpty {
                            guard !request.snapshot.effective.contains(where: { $0.name == name }), edits[name] == nil,
                                  !(catalog?.nodes.contains(name) ?? false) else { return "This name is already in use." }
                        }
                        if fields.isEmpty { edits.removeValue(forKey: name) } else { edits[name] = fields }
                        return await apply(edits, snapshot: request.snapshot, selection: name)
                    } catch { return error.localizedDescription }
                }
        }
        .sheet(item: $composition, onDismiss: refresh) { request in
            PolicyCompositionView(snapshot: request.snapshot, startWithRecommended: request.recommended, onApplied: applied)
        }
        .alert(item: $removal) { request in
            Alert(title: Text(request.restore ? "Restore \(request.id)?" : "Delete \(request.id)?"),
                  message: Text(request.restore ? "Remove this local override and use the subscription definition." : "References must be updated before this group can be removed. Use Compose to change groups and rules together."),
                  primaryButton: .destructive(Text(request.restore ? "Restore" : "Delete"), action: { change(request) }),
                  secondaryButton: .cancel())
        }
    }
    private var hasOverride: Bool {
        guard let snapshot = model.snapshot, let name = model.selection else { return false }
        return snapshot.inherited.contains { $0.name == name } && ((try? PolicyConfiguration.decodeOverrides(snapshot.stored)) ?? [:])[name] != nil
    }
    private var policyTable: some View {
        Table(rows, selection: $model.selection) {
            TableColumn("Group") { group in Text(group.name).font(DS.Typography.body.weight(.medium)).lineLimit(1).help(group.name) }.width(min: 140, ideal: 230)
            TableColumn("Type") { Text($0.type).font(DS.Typography.metadata) }.width(90)
            TableColumn("Source") { group in Text(PolicyWorkspacePresentation.source(name: group.name, overrides: model.snapshot?.stored ?? "{}"))
                    .font(DS.Typography.metadata).foregroundStyle(.secondary) }.width(100)
            TableColumn("Current") { group in Text(PolicyWorkspacePresentation.current(group, live: model.live)).font(DS.Typography.metadata).lineLimit(1)
                    .help(PolicyWorkspacePresentation.current(group, live: model.live)) }.width(min: 90, ideal: 170)
            TableColumn("Used by") { group in
                Text(model.snapshot?.usage.map { String($0.references(to: group.name).count) + ($0.issues.isEmpty ? "" : "+") } ?? "—")
                    .font(DS.Typography.metadata).monospacedDigit()
                    .help("Saved references, including disabled devices. + indicates incomplete or dynamic references. This is not live traffic.")
            }.width(58)
        }
        .frame(minHeight: 155)
        .overlay { if rows.isEmpty {
            Text(model.busy ? "Reading policies…" : model.snapshot == nil ? "Select a subscription to manage policies" : search.isEmpty ? "No policy groups · Create one with +" : "No matching groups")
                .font(DS.Typography.secondary).foregroundStyle(.secondary).padding()
        } }
        .contextMenu { Button("Edit Group…") { editSelected() }.disabled(model.selected == nil || !PolicyConfiguration.types.contains(model.selected?.type ?? "")) }
    }
    private func details(_ group: PolicyConfiguration.Group) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack {
                Text(group.name).font(DS.Typography.secondary.weight(.medium)).lineLimit(1).help(group.name)
                Spacer()
                SettingsTabs(titles: ["Members", "Used by", "Status"], selection: $detail)
            }
            if detail == 0 { members(group) }
            else if detail == 1 { usage }
            else { status(group) }
        }.padding(DS.Space.lg).frame(height: 240, alignment: .top)
    }
    private func members(_ group: PolicyConfiguration.Group) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            let actual = model.graph?.edges.filter { $0.parent == group.name }
            if let actual {
                Table(actual) {
                    TableColumn("Runtime member") { Text($0.member).lineLimit(1).help($0.member) }
                    TableColumn("Kind") { Text($0.kind) }.width(85)
                    TableColumn("Current") { Text($0.active ? "✓" : "—") }.width(60)
                }.font(DS.Typography.metadata)
            } else {
                List {
                    ForEach(group.members, id: \.self) { Text($0) }
                    ForEach(group.providers, id: \.self) { Text($0 + " · Resource").foregroundStyle(.secondary) }
                }.font(DS.Typography.metadata)
            }
            Text(actual == nil ? "Saved members · Runtime unavailable" : group.type == "load-balance" ? "Runtime members · Exit varies per connection" : "Runtime members · Membership is not a physical route")
                .font(DS.Typography.metadata).foregroundStyle(.secondary)
        }
    }
    private var usage: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            if model.references.isEmpty {
                Text(model.snapshot?.usage == nil ? "Saved references could not be read" : "No known saved references")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                Table(model.references) {
                    TableColumn("Kind") { Text($0.kind) }.width(90)
                    TableColumn("Name") { Text($0.name).lineLimit(1).help($0.name) }
                    TableColumn("Reference") { Text($0.detail).lineLimit(1).help($0.detail) }
                }.font(DS.Typography.metadata)
            }
            Text("Saved references · New traffic follows the matching rule")
                .font(DS.Typography.metadata).foregroundStyle(.secondary)
                .help((model.snapshot?.usage?.issues ?? []).joined(separator: "\n"))
        }
    }
    private func status(_ group: PolicyConfiguration.Group) -> some View {
        ScrollView {
            Grid(alignment: .leading, horizontalSpacing: 30, verticalSpacing: DS.Space.sm) {
                GridRow { Text("Source").foregroundStyle(.secondary); Text(PolicyWorkspacePresentation.source(name: group.name, overrides: model.snapshot?.stored ?? "{}")) }
                GridRow { Text("Runtime").foregroundStyle(.secondary); Text(PolicyWorkspacePresentation.verification(group, live: model.live).rawValue)
                        .help("Reads group type and explicit member order. With filters, only type is compared. Probe parameters and traffic matches are not available from this readback.") }
                GridRow { Text("Captured").foregroundStyle(.secondary); Text(model.capturedAt.map { $0.formatted(date: .omitted, time: .standard) } ?? "—").monospacedDigit() }
                GridRow { Text("Parameters").foregroundStyle(.secondary); Text("Saved configuration").help("The core validates these on Apply. The runtime API does not expose all probe, filter or timing parameters.") }
            }.font(DS.Typography.metadata).frame(maxWidth: .infinity, alignment: .leading)
            ForEach(Array(Set((model.snapshot?.usage?.issues ?? []) + (model.graph?.issues ?? []))).sorted(), id: \.self) { issue in
                Text(issue).font(DS.Typography.metadata).foregroundStyle(Color.statusWarn).frame(maxWidth: .infinity, alignment: .leading).padding(.top, DS.Space.sm)
            }
        }
    }
    private func editSelected() {
        guard let group = model.selected, let snapshot = model.snapshot else { return }
        let edits = (try? PolicyConfiguration.decodeOverrides(snapshot.stored)) ?? [:]
        editor = .init(id: group.name, isNew: edits[group.name]?["_create"] == "true", snapshot: snapshot)
    }
    private func compose(_ recommended: Bool) {
        if let snapshot = model.snapshot { composition = .init(recommended: recommended, snapshot: snapshot) }
    }
    private func refresh() { Task { await model.reload() } }
    private func refreshRuntime() { model.invalidate(); refresh() }
    private func applied() { model.message = "Saved. Runtime status is read back when the applied profile is available." }
    private func apply(_ edits: [String: [String: String]], snapshot: PolicyGroupService.Snapshot, selection: String?) async -> String? {
        do {
            let text = try PolicyConfiguration.encodeOverrides(edits)
            _ = try PolicyConfiguration.apply(source: snapshot.source, overrides: text)
            guard await PolicyGroupService.apply(text, snapshot: snapshot) else { return AppState.shared.lastOperationError ?? "Policy changes could not be applied." }
            model.selection = selection; applied(); return nil
        } catch { return error.localizedDescription }
    }
    private func change(_ request: RemovalRequest) {
        applying = true; actionError = nil
        Task { @MainActor in
            do {
                var edits = try PolicyConfiguration.decodeOverrides(request.snapshot.stored)
                if request.restore || edits[request.id]?["_create"] == "true" { edits.removeValue(forKey: request.id) }
                else { edits[request.id] = ["_delete": "true"] }
                actionError = await apply(edits, snapshot: request.snapshot, selection: model.selection)
            } catch { actionError = error.localizedDescription }
            applying = false
            await model.reload()
        }
    }
}
