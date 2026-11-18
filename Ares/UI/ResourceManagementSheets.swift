import SwiftUI
import SubscriptionKit
import Yams

struct ResourceImportSheet: View {
    let add: (String) -> String?
    @Environment(\.dismiss) private var dismiss
    @State private var links = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            Text("Import Node Links").font(DS.Typography.secondary.weight(.semibold))
            Text("One link per line · VLESS, Trojan or Shadowsocks").foregroundStyle(.secondary)
            TextEditor(text: $links).font(.system(size: 12, design: .monospaced))
                .scrollIndicators(.never).padding(DS.Space.xs)
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.control).strokeBorder(DS.line))
                .accessibilityLabel("Node links")
                .onChange(of: links) { _, _ in error = nil }
            if let error { Text(error).foregroundStyle(Color.statusBad) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Import to Draft") {
                    error = add(links)
                    if error == nil { dismiss() }
                }.buttonStyle(.borderedProminent)
                    .disabled(links.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.controlSize(.small)
        }.font(DS.Typography.metadata).padding(DS.Space.lg).frame(width: 510, height: 292)
    }
}

struct ResourceEditorSheet: View {
    let provider: Bool
    let isNew: Bool
    let save: (String, String) -> String?
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var source: String
    @State private var type = "vless"
    @State private var mode: Int
    @State private var error: String?

    init(name: String, source: String, provider: Bool, isNew: Bool, save: @escaping (String, String) -> String?) {
        self.provider = provider; self.isNew = isNew; self.save = save
        _name = State(initialValue: name)
        _source = State(initialValue: isNew ? Self.template(provider: provider, type: "vless") : source)
        _mode = State(initialValue: provider && !isNew && (try? ManagedResources.document(source)["type"]?.string) != "http" ? 1 : 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            Text((isNew ? "Add " : "Edit ") + (provider ? "Node Provider" : "Node")).font(DS.Typography.secondary.weight(.semibold))
            TextField("Name", text: $name).textFieldStyle(.roundedBorder)
            if isNew && !provider {
                Picker("Protocol", selection: $type) {
                    ForEach(["vless", "trojan", "ss", "http", "socks5"], id: \.self) { Text($0 == "ss" ? "Shadowsocks" : $0.uppercased()).tag($0) }
                }.controlSize(.small).onChange(of: type) { _, _ in source = Self.template(provider: false, type: type) }
            }
            SettingsTabs(titles: ["Form", "Source"], selection: $mode)
            if mode == 0 && (!provider || (try? ManagedResources.document(source)["type"]?.string) == "http") {
                ScrollView {
                    ResourceNodeForm(source: $source, provider: provider).id(type)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if mode == 0 {
                Text("Use Source to edit File and Inline providers.").foregroundStyle(.secondary)
                    .frame(maxHeight: .infinity, alignment: .topLeading)
            } else {
                TextEditor(text: $source).font(.system(size: 12, design: .monospaced))
                    .padding(DS.Space.xs).overlay(RoundedRectangle(cornerRadius: DS.Radius.control).strokeBorder(DS.line))
                    .accessibilityLabel("Resource YAML")
            }
            if let error { Text(error).font(DS.Typography.metadata).foregroundStyle(Color.statusBad) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save to Draft") {
                    error = save(name, source)
                    if error == nil { dismiss() }
                }.buttonStyle(.borderedProminent).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.controlSize(.small)
        }.font(DS.Typography.secondary).padding(DS.Space.lg).frame(width: 510, height: 490)
            .scrollIndicators(.never, axes: [.horizontal, .vertical])
    }

    private static func template(provider: Bool, type: String) -> String {
        if provider { return "type: http\nurl: https://example.invalid/nodes.yaml\ninterval: 3600\n" }
        let config: String
        switch type {
        case "vless": config = "uuid: \ntls: true\n"
        case "trojan": config = "password: \n"
        case "ss": config = "cipher: aes-128-gcm\npassword: \n"
        default: config = ""
        }
        return "type: \(type)\nserver: \nport: 443\n" + config
    }
}

/// Uses the existing policy transaction and changes only this group's explicit members or providers.
struct ResourcePolicySheet: View {
    let name: String
    let provider: Bool
    let revision: String
    let onApplied: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var snapshot: PolicyGroupService.Snapshot?
    @State private var groupName = ""
    @State private var loading = true
    @State private var saving = false
    @State private var error: String?
    private var groups: [PolicyConfiguration.Group] {
        snapshot?.effective.filter { PolicyConfiguration.types.contains($0.type) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } ?? []
    }
    private var selected: PolicyConfiguration.Group? { groups.first { $0.name == groupName } }
    private var alreadyIncluded: Bool { selected.map { (provider ? $0.providers : $0.members).contains(name) } ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            Text("Add to Policy").font(DS.Typography.secondary.weight(.semibold))
            Text(name).foregroundStyle(.secondary).lineLimit(1).help(name)
            if loading { ProgressView().controlSize(.small) }
            else if groups.isEmpty { Text("No editable groups. Create one in Policies first.").foregroundStyle(.secondary) }
            else {
                Picker("Policy group", selection: $groupName) {
                    Text("Choose a group").tag("")
                    ForEach(groups, id: \.name) { Text($0.name).tag($0.name) }
                }.onChange(of: groupName) { _, _ in error = nil }
                if let selected {
                    Text(alreadyIncluded ? "Already listed in \(selected.name)." : provider ? "Add this provider to \(selected.name)." : "Append this node to \(selected.name)’s explicit members.")
                        .font(DS.Typography.metadata).foregroundStyle(.secondary)
                }
                Text("Routing rules are unchanged. A running core restarts to apply the policy.")
                    .font(DS.Typography.metadata).foregroundStyle(.secondary)
            }
            if let error { Text(error).font(DS.Typography.metadata).foregroundStyle(Color.statusBad) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(saving ? "Applying…" : "Apply to Policy") { Task { await apply() } }.buttonStyle(.borderedProminent)
                    .disabled(selected == nil || alreadyIncluded || loading)
            }.controlSize(.small)
        }.font(DS.Typography.secondary).padding(DS.Space.lg).frame(width: 450).disabled(saving).interactiveDismissDisabled(saving)
            .task {
                defer { loading = false }
                do {
                    let current = try await PolicyGroupService.load()
                    guard current.revision == revision, try available(in: current) else {
                        error = "This resource is no longer available. Reload Resources before assigning it."; return
                    }
                    snapshot = current
                } catch { self.error = "Policy groups could not be loaded." }
            }
    }

    private func available(in snapshot: PolicyGroupService.Snapshot) throws -> Bool {
        let catalog = try PolicyConfiguration.catalog(snapshot.source)
        return (provider ? catalog.providers : catalog.nodes).contains(name)
    }

    private func apply() async {
        guard let snapshot, let selected, !alreadyIncluded, !saving else { return }
        saving = true; error = nil
        defer { saving = false }
        do {
            let current = try await PolicyGroupService.load()
            guard current.revision == revision, current.stored == snapshot.stored, try available(in: current),
                  let group = current.effective.first(where: { $0.name == selected.name }),
                  group.members == selected.members, group.providers == selected.providers, group.type == selected.type else {
                error = "Resources or policies changed. Reopen this sheet to review the latest groups."; return
            }
            var overrides = try PolicyConfiguration.decodeOverrides(current.stored)
            let list = provider ? group.providers : group.members
            overrides[group.name, default: [:]][provider ? "use" : "proxies"] = try PolicyConfiguration.list(list + [name])
            let encoded = try PolicyConfiguration.encodeOverrides(overrides)
            if await PolicyGroupService.apply(encoded, snapshot: current) {
                onApplied(group.name); dismiss()
            } else { error = "Could not apply this policy. Review the current configuration and try again." }
        } catch { self.error = "Could not read current resources or policies." }
    }
}
