import SwiftUI
import SubscriptionKit

struct ManagedResourcesView: View {
    @ObservedObject private var profiles = ProfileService.shared
    @ObservedObject private var controller = ClashController.shared
    @EnvironmentObject private var core: ClashViewModel
    @EnvironmentObject private var app: AppState
    @State private var snapshot: ManagedWorkspaceService.Snapshot?
    @State private var draft = ManagedWorkspaceService.Document()
    @State private var entries: [ManagedResources.Entry] = []
    @State private var inheritedIDs = Set<String>()
    @State private var selection: String?
    @State private var search = ""
    @State private var tab = 0
    @State private var sheet: Sheet?
    @State private var busy = false
    @State private var loading = true
    @State private var error: String?
    @State private var result: String?

    private struct Change: Identifiable {
        let id: String
        let name: String
        let provider: Bool
        let action: String
    }
    private struct Item: Identifiable {
        let name: String
        let provider: Bool
        var id: String { (provider ? "provider:" : "node:") + name }
    }
    private enum Sheet: Identifiable {
        case edit(Item?, String), importLinks, apply, policy(Item)
        var id: String {
            switch self { case .edit: "edit"; case .importLinks: "import"; case .apply: "apply"; case .policy: "policy" }
        }
    }

    private var providers: Bool { tab == 1 }
    private var category: [ManagedResources.Entry] { entries.filter { $0.provider == providers } }
    private var filtered: [ManagedResources.Entry] {
        category.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.type.localizedCaseInsensitiveContains(search) }
    }
    private var selected: ManagedResources.Entry? { filtered.first { $0.id == selection } }
    private var changed: Bool { snapshot.map { draft.resources != $0.document.resources } ?? false }
    private var ready: Bool { snapshot?.revision == profiles.activeProfileRevision && !loading }
    private var canOperate: Bool { !busy && !app.isPerformingNetworkOperation && !core.isToggling }
    private var changes: [Change] {
        guard let saved = snapshot?.document.resources else { return [] }
        return diff(before: saved.nodes, removedBefore: saved.removedNodes, after: draft.resources.nodes, removedAfter: draft.resources.removedNodes, provider: false)
            + diff(before: saved.providers, removedBefore: saved.removedProviders, after: draft.resources.providers, removedAfter: draft.resources.removedProviders, provider: true)
    }

    var body: some View {
        VStack(spacing: 0) {
            tools
            DSCard(padding: 0, spacing: 0) {
                draftBar
                if !ready || filtered.isEmpty { emptyState }
                else {
                    table
                    if let selected {
                        Divider()
                        details(selected)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card))
            .padding(.horizontal, DS.Space.lg).padding(.bottom, DS.Space.lg)
            if let message = error ?? result {
                Text(message).font(DS.Typography.metadata)
                    .foregroundStyle(error == nil ? Color.secondary : Color.statusBad)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DS.Space.lg).padding(.bottom, DS.Space.md)
            }
        }
        .font(DS.Typography.secondary).background(DS.canvas)
        .scrollIndicators(.never, axes: [.horizontal, .vertical])
        .toolbar {
            let singular = category.count == 1
            CollectionTitleToolbar(title: "Resources", count: ready ? category.count : nil,
                                   unit: providers ? (singular ? "Provider" : "Providers") : (singular ? "Node" : "Nodes"))
        }
        .onAppear {
            if app.showNodeProvidersOnEntry { tab = 1; app.showNodeProvidersOnEntry = false }
        }
        .task(id: profiles.activeProfileRevision) {
            let lostDraft = changed || sheet != nil
            sheet = nil
            select(nil); search = ""
            await load()
            if lostDraft, !Task.isCancelled, error == nil { result = "Subscription changed. Unapplied edits were discarded." }
        }
        .sheet(item: $sheet) { active in
            switch active {
            case .edit(let item, let source):
                ResourceEditorSheet(name: item?.name ?? "", source: source, provider: providers, isNew: item == nil) { name, text in
                    save(item, name: name, source: text)
                }
            case .importLinks: ResourceImportSheet(add: importLinks)
            case .apply: review
            case .policy(let item):
                ResourcePolicySheet(name: item.name, provider: item.provider, revision: snapshot?.revision ?? "") {
                    result = "Added \(item.name) to \($0)."
                }
            }
        }
    }

    private var tools: some View {
        DSCard(padding: DS.Space.md) {
            HStack(spacing: DS.Space.md) {
                SettingsTabs(titles: ["Nodes", "Node Providers"], selection: Binding(get: { tab }, set: {
                    tab = $0; select(nil); search = ""
                }))
                Spacer(minLength: 0)
                if ready {
                    TextField(providers ? "Search providers" : "Search nodes", text: $search)
                        .textFieldStyle(.roundedBorder).frame(minWidth: 115, idealWidth: 165, maxWidth: 180)
                    if !providers { Button("Import Links…") { sheet = .importLinks }.fixedSize() }
                    Button(providers ? "Add Provider…" : "Add Node…") { sheet = .edit(nil, "") }.fixedSize()
                    Menu {
                        if changed { Button("Discard Draft", role: .destructive) { discard() } }
                        let removed = removedItems
                        if !removed.isEmpty {
                            Menu("Restore Removed Resource") {
                                ForEach(removed) { item in Button(item.name + (item.provider ? " · Provider" : " · Node")) { restore(item) } }
                            }
                        }
                        Button("Reload Resources") { Task { await load() } }.disabled(changed)
                    } label: { Image(systemName: "ellipsis") }
                    .fixedSize().menuStyle(.borderlessButton).accessibilityLabel("Resource actions")
                }
            }.buttonStyle(.borderless).controlSize(.small).disabled(!canOperate)
        }.padding(.horizontal, DS.Space.lg).padding(.top, DS.Space.pageTop).padding(.bottom, DS.Space.md)
    }

    private var emptyState: some View {
        VStack(spacing: DS.Space.sm) {
            if loading { ProgressView().controlSize(.small) }
            else if !ready {
                if profiles.activeProfileID == nil {
                    Text("Select a subscription to manage resources.")
                    Button("Create Local Workspace") {
                        do { try profiles.createResourceWorkspace() }
                        catch let failure as ManagedResources.Failure { self.error = failure.localizedDescription }
                        catch { self.error = "Could not create a local workspace." }
                    }
                } else {
                    Text("Resources could not be loaded.")
                    Button("Retry") { Task { await load() } }
                }
            } else {
                Text(!search.isEmpty ? "No matching resources" : providers ? "No node providers" : "No static nodes")
                if search.isEmpty && !providers {
                    Text("Import a node link or add a node manually.").font(DS.Typography.metadata)
                }
            }
        }.foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var table: some View {
        Table(filtered, selection: $selection) {
            TableColumn("Name") { Text($0.name).font(DS.Typography.secondary.weight(.medium)).lineLimit(1).help($0.name) }
            TableColumn(providers ? "Type" : "Protocol") { Text(protocolName($0.type)).foregroundStyle(.secondary) }.width(85)
            TableColumn("Source") { Text(sourceName($0)).foregroundStyle(.secondary) }.width(110)
            TableColumn("Status") { item in
                Text(changeFor(item) == nil ? "—" : "Draft").foregroundStyle(changeFor(item) == nil ? Color.secondary : Color.statusWarn)
            }.width(85)
        }.alternatingRowBackgrounds(.disabled).font(DS.Typography.metadata)
    }

    @ViewBuilder private var draftBar: some View {
        if changed && ready {
            HStack(spacing: DS.Space.md) {
                Label(changes.count == 1 ? "1 draft change" : "\(changes.count) draft changes", systemImage: "square.and.pencil")
                Spacer()
                Button("Review & Apply…") { sheet = .apply }.buttonStyle(.borderedProminent).disabled(!canOperate)
            }.font(DS.Typography.metadata).controlSize(.small).padding(.horizontal, DS.Space.lg).padding(.vertical, DS.Space.sm)
                .background(DS.surface)
        }
    }

    private func details(_ entry: ManagedResources.Entry) -> some View {
        let item = Item(name: entry.name, provider: entry.provider)
        let change = changeFor(entry)
        return VStack(alignment: .leading, spacing: DS.Space.sm) {
            HStack(spacing: DS.Space.md) {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text(item.name).font(DS.Typography.secondary.weight(.semibold)).lineLimit(1).help(item.name)
                    Text(protocolName(entry.type) + " · " + sourceName(entry) + (change == nil ? "" : " · Draft"))
                        .font(DS.Typography.metadata).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: DS.Space.sm)
                Button("Edit…") { edit(item) }.fixedSize()
                Button("Add to Policy…") { sheet = .policy(item) }.fixedSize().disabled(changed)
                    .help(changed ? "Apply resource changes before editing a policy." : "Add this resource to an existing policy group.")
                Menu {
                    if entry.local && inheritedIDs.contains(item.id) {
                        Button("Restore Inheritance") { restore(item) }
                    }
                    Button("Remove Resource", role: .destructive) { remove(item) }
                } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Selected resource actions")
            }.controlSize(.small).disabled(!canOperate)
            if item.provider {
                NodeProviderDetails(name: item.name, canRead: change == nil && ready)
                    .id(item.id).environmentObject(controller)
            }
        }.padding(DS.Space.lg)
    }

    private var review: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            Text("Review Resource Changes").font(DS.Typography.secondary.weight(.semibold))
            Table(changes) {
                TableColumn("Resource") { Text($0.name).lineLimit(1).help($0.name) }
                TableColumn("Kind") { Text($0.provider ? "Provider" : "Node") }.width(72)
                TableColumn("Change") { Text($0.action) }.width(135)
            }.alternatingRowBackgrounds(.disabled).font(DS.Typography.metadata)
                .frame(height: 30 + CGFloat(min(changes.count, 7)) * 26)
                .scrollIndicators(.never)
            Text("If the core is running, Apply restarts it. Existing policy references are validated before the switch.")
                .font(DS.Typography.metadata).foregroundStyle(.secondary)
            if let error { Text(error).font(DS.Typography.metadata).foregroundStyle(Color.statusBad) }
            HStack {
                Spacer()
                Button("Cancel") { sheet = nil }.keyboardShortcut(.cancelAction)
                Button(busy ? "Applying…" : "Apply") { Task { await apply() } }
                    .buttonStyle(.borderedProminent).disabled(!ready || !changed || !canOperate)
            }.controlSize(.small)
        }.padding(DS.Space.lg).frame(width: 560).background(DS.canvas)
            .disabled(busy).interactiveDismissDisabled(busy)
    }

    private var removedItems: [Item] {
        draft.resources.removedNodes.sorted().map { Item(name: $0, provider: false) }
            + draft.resources.removedProviders.sorted().map { Item(name: $0, provider: true) }
    }
    private func protocolName(_ value: String) -> String {
        switch value { case "ss": "Shadowsocks"; case "inline", "file": value.capitalized; default: value.uppercased() }
    }
    private func sourceName(_ entry: ManagedResources.Entry) -> String {
        entry.local ? (inheritedIDs.contains(entry.id) ? "Local override" : "Local") : "Subscription"
    }
    private func changeFor(_ item: ManagedResources.Entry) -> Change? {
        guard let saved = snapshot?.document.resources else { return nil }
        let name = item.name
        let before = item.provider ? saved.providers[name] : saved.nodes[name]
        let after = item.provider ? draft.resources.providers[name] : draft.resources.nodes[name]
        let removed = item.provider ? saved.removedProviders.contains(name) : saved.removedNodes.contains(name)
        guard before != after || removed else { return nil }
        let action = removed ? "Restore" : after == nil ? "Restore inheritance" : (before != nil || inheritedIDs.contains(item.id)) ? "Edit" : "Add"
        return .init(id: item.id, name: name, provider: item.provider, action: action)
    }
    private func diff(before: [String: String], removedBefore: Set<String>, after: [String: String], removedAfter: Set<String>, provider: Bool) -> [Change] {
        Set(before.keys).union(after.keys).union(removedBefore).union(removedAfter).sorted().compactMap { name in
            let wasRemoved = removedBefore.contains(name), isRemoved = removedAfter.contains(name)
            guard before[name] != after[name] || wasRemoved != isRemoved else { return nil }
            let item = Item(name: name, provider: provider)
            let action = isRemoved ? "Remove" : wasRemoved ? "Restore" : after[name] == nil
                ? (inheritedIDs.contains(item.id) ? "Restore inheritance" : "Remove")
                : (before[name] != nil || inheritedIDs.contains(item.id) ? "Edit" : "Add")
            return Change(id: item.id, name: name, provider: provider, action: action)
        }
    }
    private func select(_ item: Item?) { selection = item?.id }
    private func edit(_ item: Item) {
        guard let snapshot, ready else { return }
        do {
            sheet = .edit(item, try ManagedResources.entry(source: snapshot.source, draft: draft.resources, name: item.name, provider: item.provider))
        } catch { self.error = "Resource could not be read." }
    }
    private func save(_ original: Item?, name: String, source: String) -> String? {
        let item = Item(name: name.trimmingCharacters(in: .whitespacesAndNewlines), provider: original?.provider ?? providers)
        guard ready, ManagedResources.validName(item.name) else { return "Enter a valid resource name." }
        if original?.id != item.id && entries.contains(where: { $0.id == item.id }) { return "That name is already in use." }
        var candidate = draft.resources
        if let original, original.id != item.id { remove(original, from: &candidate) }
        if item.provider { candidate.providers[item.name] = source; candidate.removedProviders.remove(item.name) }
        else { candidate.nodes[item.name] = source; candidate.removedNodes.remove(item.name) }
        return stage(candidate, selecting: item)
    }
    private func remove(_ item: Item, from candidate: inout ManagedResources.Draft) {
        if item.provider {
            candidate.providers.removeValue(forKey: item.name)
            if inheritedIDs.contains(item.id) { candidate.removedProviders.insert(item.name) }
        } else {
            candidate.nodes.removeValue(forKey: item.name)
            if inheritedIDs.contains(item.id) { candidate.removedNodes.insert(item.name) }
        }
    }
    private func remove(_ item: Item) {
        var candidate = draft.resources
        remove(item, from: &candidate)
        error = stage(candidate, selecting: nil)
    }
    private func restore(_ item: Item) {
        var candidate = draft.resources
        if item.provider { candidate.providers.removeValue(forKey: item.name); candidate.removedProviders.remove(item.name) }
        else { candidate.nodes.removeValue(forKey: item.name); candidate.removedNodes.remove(item.name) }
        error = stage(candidate, selecting: item)
    }
    private func importLinks(_ text: String) -> String? {
        guard ready else { return "Reload resources before importing." }
        do {
            let imported = try ManagedResources.importLinks(text)
            let occupied = Set(entries.filter { !$0.provider }.map(\.name)).union(draft.resources.removedNodes)
            guard Set(imported.keys).isDisjoint(with: occupied) else { return "An imported name already exists. Rename it before importing." }
            var candidate = draft.resources
            candidate.nodes.merge(imported) { _, value in value }
            let first = imported.keys.sorted().first.map { Item(name: $0, provider: false) }
            let failure = stage(candidate, selecting: first)
            if failure == nil { result = imported.count == 1 ? "1 node added to draft." : "\(imported.count) nodes added to draft." }
            return failure
        } catch let failure as ManagedResources.Failure { return failure.localizedDescription }
        catch { return "Could not import these links." }
    }
    private func stage(_ candidate: ManagedResources.Draft, selecting item: Item?) -> String? {
        guard let snapshot, ready else { return "Reload resources before editing." }
        do {
            let updated = try ManagedResources.entries(source: snapshot.source, draft: candidate)
            draft.resources = candidate; entries = updated; error = nil; result = nil
            if let item { tab = item.provider ? 1 : 0; search = "" }
            select(item)
            return nil
        } catch let failure as ManagedResources.Failure { return failure.localizedDescription }
        catch { return "Invalid resource configuration. Check the fields and try again." }
    }
    private func discard() {
        guard let snapshot, ready else { return }
        error = stage(snapshot.document.resources, selecting: nil)
    }
    private func load(retaining id: String? = nil) async {
        loading = true; error = nil; result = nil
        let revision = profiles.activeProfileRevision
        defer { if revision == profiles.activeProfileRevision, !Task.isCancelled { loading = false } }
        do {
            let value = try await ManagedWorkspaceService.load()
            let saved = try ManagedResources.entries(source: value.source, draft: value.document.resources)
            let inherited = try ManagedResources.entries(source: value.source, draft: .init())
            guard revision == profiles.activeProfileRevision, !Task.isCancelled else { return }
            snapshot = value; draft = value.document; entries = saved; inheritedIDs = Set(inherited.map(\.id))
            selection = saved.contains { $0.id == id } ? id : nil
        } catch {
            guard revision == profiles.activeProfileRevision, !Task.isCancelled else { return }
            snapshot = nil; draft = .init(); entries = []; inheritedIDs = []; selection = nil
        }
    }
    private func apply() async {
        guard let snapshot, ready, changed, canOperate else { return }
        let id = selection
        busy = true; error = nil
        defer { busy = false }
        do {
            try await ManagedWorkspaceService.apply(draft, snapshot: snapshot)
            guard profiles.activeProfileRevision == snapshot.revision else { return }
            sheet = nil
            await load(retaining: id)
            result = ready ? "Resource changes saved." : "Changes saved. Reload to see the updated resources."
        } catch let failure as ManagedResources.Failure { error = failure.localizedDescription }
        catch { self.error = "Resource validation failed. Check dependencies and try again." }
    }
}
