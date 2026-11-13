import SwiftUI
import SubscriptionKit

struct ManagedResourcesView: View {
    @ObservedObject private var profiles = ProfileService.shared
    @State private var snapshot: ManagedWorkspaceService.Snapshot?
    @State private var draft = ManagedWorkspaceService.Document()
    @State private var entries: [ManagedResources.Entry] = []
    @State private var selection: String?
    @State private var search = ""
    @State private var tab = 0
    @State private var name = ""
    @State private var source = ""
    @State private var editMode = 0
    @State private var newType = "vless"
    @State private var links = ""
    @State private var importing = false
    @State private var editing = false
    @State private var busy = false
    @State private var error: String?
    @State private var confirming = false
    @State private var showRuntime = false
    private var changed: Bool { snapshot.map { draft != $0.document } ?? false }
    private var filtered: [ManagedResources.Entry] { entries.filter { $0.provider == (tab == 1) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) } }
    private var selected: ManagedResources.Entry? { entries.first { $0.id == selection } }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                SettingsTabs(titles: ["Nodes", "Providers"], selection: $tab).disabled(editing || busy)
                Spacer()
                if changed { Text("Unsaved changes").font(DS.Typography.metadata).foregroundStyle(.secondary) }
                Button("Apply") { confirming = true }.disabled(!changed || busy || editing)
            }.padding(.horizontal, 16).padding(.top, 8)
            CollectionTools(placeholder: "Search resources", search: $search) {
                Button { newEntry() } label: { Image(systemName: "plus") }.help("Add resource")
                Button { importing = true } label: { Image(systemName: "square.and.arrow.down") }.help("Import node links")
                Button { showRuntime = true } label: { Image(systemName: "waveform.path.ecg") }.help("Provider status and health checks")
                Button { Task { await load() } } label: { Image(systemName: "arrow.counterclockwise") }.help("Discard draft and reload").disabled(!changed)
            }.disabled(busy || editing || snapshot == nil)
            if let error { Text(error).font(DS.Typography.metadata).foregroundStyle(Color.statusBad).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.bottom, 8) }
            HSplitView {
                Table(filtered, selection: $selection) {
                    TableColumn("Name") { Text($0.name).lineLimit(1) }
                    TableColumn("Type") { Text($0.type).foregroundStyle(.secondary) }.width(70)
                    TableColumn("Source") { Text($0.local ? "Local" : "Subscription").foregroundStyle(.secondary) }.width(85)
                }.frame(minWidth: 280).disabled(editing)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if editing {
                            TextField("Name", text: $name).textFieldStyle(.roundedBorder)

                            if selected == nil && tab == 0 {
                                Picker("Protocol", selection: $newType) {
                                    ForEach(["vless", "trojan", "ss", "http", "socks5"], id: \.self) { Text($0.uppercased()).tag($0) }
                                }.controlSize(.small).onChange(of: newType) { _, _ in source = nodeTemplate() }
                            }
                            SettingsTabs(titles: ["Form", "Source"], selection: $editMode)
                            if editMode == 0 { ResourceNodeForm(source: $source, provider: tab == 1).id((selection ?? "new") + newType) }
                            else { TextEditor(text: $source).font(.system(size: 12, design: .monospaced)).frame(minHeight: 280)
                                .scrollIndicators(.never).border(DS.line)
                                .help("YAML resource mapping. Advanced and unknown fields are preserved. Credentials are stored in a private local file.") }
                            HStack {
                                Button("Cancel") { editing = false }
                                Spacer()
                                Button("Save to Draft") { saveEntry() }.buttonStyle(.borderedProminent)
                            }
                        } else if let selected {
                            Text(selected.name).font(DS.Typography.secondary.weight(.medium))
                            LabeledContent("Type", value: selected.type)
                            LabeledContent("Source", value: selected.local ? "Local override" : "Subscription")
                            HStack {
                                Button("Edit") { edit(selected) }
                                Button("Remove", role: .destructive) { remove(selected) }
                                if selected.local { Button("Restore Inheritance") { restore(selected) } }
                            }.controlSize(.small)
                            Text("Changes are validated with policy, rule and listener references before activation.").font(DS.Typography.metadata).foregroundStyle(.secondary)
                            Button("Compose Policies") { AppState.shared.selection = .policies }.disabled(changed)
                        } else {
                            Text(filtered.isEmpty ? "No resources" : "Select a resource").foregroundStyle(.secondary)
                            if snapshot != nil { Button("Add Resource") { newEntry() } }
                            else { Button("Create Local Workspace") {
                                do { try profiles.createResourceWorkspace(); Task { await load() } }
                                catch let failure as ManagedResources.Failure { error = failure.localizedDescription }
                                catch { self.error = "Could not create a local workspace." }
                            } }
                        }
                    }.font(DS.Typography.secondary).padding(16).frame(maxWidth: .infinity, alignment: .leading)
                }.frame(minWidth: 300).scrollIndicators(.never)
            }.disabled(busy).padding(.horizontal, 16)
            HStack {
                Text("Current subscription").foregroundStyle(.secondary)
                Spacer()
                if !draft.resources.removedNodes.isEmpty || !draft.resources.removedProviders.isEmpty {
                    Button("Restore Removed Resources") {
                        draft.resources.removedNodes = []; draft.resources.removedProviders = []; refreshEntries()
                    }.buttonStyle(.borderless).disabled(busy)
                }
            }.font(DS.Typography.metadata).padding(16)
        }.font(DS.Typography.secondary).background(DS.canvas)
        .toolbar { CollectionTitleToolbar(title: "Resources", count: entries.count, unit: "resources") }
        .task(id: profiles.activeProfileRevision) { await load() }
        .onChange(of: tab) { _, _ in selection = nil; editing = false }
        .sheet(isPresented: $showRuntime) { ProxyResourcesView() }
        .sheet(isPresented: $importing) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Import Node Links").font(DS.Typography.secondary.weight(.semibold))
                Text("VLESS · Trojan · Shadowsocks").font(DS.Typography.metadata).foregroundStyle(.secondary)
                TextEditor(text: $links).font(.system(size: 12, design: .monospaced)).frame(height: 220)
                HStack { Button("Cancel") { importing = false; links = "" }; Spacer(); Button("Import to Draft") { importLinks() } }
            }.padding(20).frame(width: 560)
        }
        .confirmationDialog("Apply resource changes?", isPresented: $confirming) {
            Button("Apply") { Task { await apply() } }
        } message: { Text("The current core will restart if running. Invalid references are rejected. Subscription files are preserved.") }
    }
    private func refreshEntries() {
        guard let snapshot else { entries = []; return }
        do { entries = try ManagedResources.entries(source: snapshot.source, draft: draft.resources); error = nil }
        catch { self.error = "Resource draft is invalid. Review the configuration." }
    }
    private func newEntry() {
        selection = nil; name = ""; editing = true; editMode = 0
        source = tab == 1 ? "type: http\nurl: https://example.com/nodes.yaml\ninterval: 3600\n" : nodeTemplate()
    }
    private func nodeTemplate() -> String {
        let auth: String
        switch newType {
        case "vless": auth = "uuid: \ntls: true\n"
        case "trojan": auth = "password: \n"
        case "ss": auth = "cipher: " + ["aes", "128", "gcm"].joined(separator: "-") + "\npassword: \n"
        default: auth = ""
        }
        return "type: \(newType)\nserver: example.com\nport: 443\n" + auth
    }
    private func edit(_ item: ManagedResources.Entry) {
        guard let snapshot else { return }
        do { source = try ManagedResources.entry(source: snapshot.source, draft: draft.resources, name: item.name, provider: item.provider); name = item.name; editing = true; editMode = item.provider && item.type != "http" ? 1 : 0 }
        catch { self.error = "Resource could not be read." }
    }
    private func saveEntry() {
        guard let snapshot else { return }
        do {
            guard ManagedResources.validName(name) else { throw ManagedResources.Failure.invalid("Use a unique resource name.") }
            if selected == nil, entries.contains(where: { $0.name == name && $0.provider == (tab == 1) }) { throw ManagedResources.Failure.invalid("That resource already exists. Select Edit to change it.") }
            var candidate = draft.resources
            if let selected, selected.name != name {
                guard !entries.contains(where: { $0.name == name && $0.provider == selected.provider }) else { throw ManagedResources.Failure.invalid("That name is already used.") }
                if selected.provider { candidate.providers.removeValue(forKey: selected.name); candidate.removedProviders.insert(selected.name) }
                else { candidate.nodes.removeValue(forKey: selected.name); candidate.removedNodes.insert(selected.name) }
            }
            if tab == 1 { candidate.providers[name] = source; candidate.removedProviders.remove(name) }
            else { candidate.nodes[name] = source; candidate.removedNodes.remove(name) }
            _ = try ManagedResources.apply(source: snapshot.source, draft: candidate)
            draft.resources = candidate; editing = false; selection = nil; refreshEntries()
        } catch let failure as ManagedResources.Failure { error = failure.localizedDescription }
        catch { self.error = "Invalid YAML. Check field names and value types." }
    }
    private func remove(_ item: ManagedResources.Entry) {
        if item.provider { draft.resources.providers.removeValue(forKey: item.name); draft.resources.removedProviders.insert(item.name) }
        else { draft.resources.nodes.removeValue(forKey: item.name); draft.resources.removedNodes.insert(item.name) }
        selection = nil; refreshEntries()
    }
    private func restore(_ item: ManagedResources.Entry) {
        if item.provider { draft.resources.providers.removeValue(forKey: item.name) } else { draft.resources.nodes.removeValue(forKey: item.name) }
        selection = nil; refreshEntries()
    }
    private func importLinks() {
        do {
            let imported = try ManagedResources.importLinks(links)
            guard Set(imported.keys).isDisjoint(with: Set(entries.filter { !$0.provider }.map(\.name))) else { throw ManagedResources.Failure.invalid("Imported names conflict with existing nodes. Rename them before importing.") }
            draft.resources.nodes.merge(imported) { _, new in new }; links = ""; importing = false; tab = 0; refreshEntries()
        } catch let failure as ManagedResources.Failure { error = failure.localizedDescription; importing = false }
        catch { self.error = "Could not import these links."; importing = false }
    }
    @MainActor private func load() async {
        busy = true; editing = false; snapshot = nil; entries = []; selection = nil
        defer { busy = false }
        do { let value = try await ManagedWorkspaceService.load(); guard !Task.isCancelled else { return }; snapshot = value; draft = value.document; refreshEntries() }
        catch { guard !Task.isCancelled else { return }; self.error = "Select a subscription to manage resources. Configuration could not be loaded." }
    }
    @MainActor private func apply() async {
        guard let snapshot else { return }; busy = true
        do { try await ManagedWorkspaceService.apply(draft, snapshot: snapshot); await load() }
        catch let failure as ManagedResources.Failure { error = failure.localizedDescription }
        catch { self.error = "Resource validation failed. Check dependencies and reload." }
        busy = false
    }
}
