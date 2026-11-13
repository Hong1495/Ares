import SwiftUI
import SubscriptionKit

/// One isolated draft for group structure and its local routing rules. No preference writes before Apply.
struct PolicyCompositionView: View {
    let snapshot: PolicyGroupService.Snapshot
    var startWithRecommended = false
    @Environment(\.dismiss) private var dismiss
    @State private var edits: [String: [String: String]] = [:]
    @State private var groups: [PolicyConfiguration.Group] = []
    @State private var selection: String?
    @State private var editing: EditorTarget?
    @State private var name = ""
    @State private var rules = ""
    @State private var ruleType = "DOMAIN-SUFFIX"
    @State private var ruleValue = ""
    @State private var sourceMode = false
    @State private var ruleSelection: UUID?
    @State private var ruleDocument = RuleDraftDocument("")
    @State private var error: String?
    @State private var applying = false
    @State private var tab = 0
    @State private var recommendation: String?
    private struct EditorTarget: Identifiable { let id: String; let isNew: Bool }
    private var catalog: PolicyConfiguration.Catalog? { try? PolicyConfiguration.catalog(snapshot.source) }
    private var conflicts: [String] {
        edits.keys.filter { edits[$0]?["_create"] == "true" && snapshot.inherited.map(\.name).contains($0) }.sorted()
    }
    private var stale: [String] {
        edits.keys.filter { key in
            edits[key]?["_delete"] != "true" && edits[key]?["_create"] != "true" && !snapshot.inherited.contains { $0.name == key }
        }.sorted()
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Compose Policies").font(DS.Typography.secondary.weight(.semibold)).fixedSize()
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Apply Changes") { apply() }.buttonStyle(.borderedProminent)
                    .disabled(edits == (try? PolicyConfiguration.decodeOverrides(snapshot.stored)) && rules == snapshot.localRules)
            }.controlSize(.small).padding(DS.Space.lg).disabled(applying)
            HStack {
                SettingsTabs(titles: ["Groups", "Routing Rules"], selection: $tab)
                Spacer()
                Text("Draft").font(DS.Typography.metadata).foregroundStyle(.secondary)
            }.padding(.horizontal, DS.Space.lg).padding(.bottom, DS.Space.md)
            Divider()
            Group {
                if tab == 0 { groupList } else { routingRules }
            }.disabled(applying)
            if let error { Text(error).font(DS.Typography.metadata).foregroundStyle(Color.statusBad).textSelection(.enabled).padding(DS.Space.md) }
            if !conflicts.isEmpty {
                Text("Local names now used by the subscription: " + conflicts.joined(separator: ", ") + ". Select each group and restore inheritance before applying.")
                    .font(DS.Typography.metadata).foregroundStyle(Color.statusWarn).padding(DS.Space.md)
            }
            if !stale.isEmpty {
                HStack {
                    Text("Missing subscription groups: " + stale.joined(separator: ", ")).lineLimit(2)
                    Spacer()
                    Button("Remove Stale Overrides") { for key in stale { edits.removeValue(forKey: key) }; refresh() }
                }.font(DS.Typography.metadata).padding(DS.Space.md)
            }
            Text("Draft · Apply to activate").help("Changes stay in this draft until Apply. Rules run before subscription rules. Invalid references or cycles prevent activation.")
                .font(DS.Typography.metadata).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(DS.Space.lg)
        }.frame(minWidth: 820, minHeight: 570).background(DS.canvas).scrollIndicators(.never, axes: [.horizontal, .vertical]).interactiveDismissDisabled(applying)
        .onAppear {
            rules = snapshot.localRules; ruleDocument = RuleDraftDocument(rules)
            do { edits = try PolicyConfiguration.decodeOverrides(snapshot.stored); refresh(); if startWithRecommended { addRecommended() } }
            catch { self.error = "Saved policy overrides could not be decoded." }
        }
        .sheet(item: $editing) { target in
            PolicyStructureEditor(name: target.id, isNew: target.isNew,
                group: groups.first { $0.name == target.id }, inherited: snapshot.inherited.first { $0.name == target.id }, override: edits[target.id] ?? [:],
                targets: Array(Set((catalog?.nodes ?? []) + groups.map(\.name) + ["DIRECT", "REJECT", "REJECT-DROP", "PASS"])).filter { $0 != target.id }.sorted(),
                providers: catalog?.providers ?? []) { fields in
                    if fields.isEmpty { edits.removeValue(forKey: target.id) } else { edits[target.id] = fields }; selection = target.id; refresh()
                }
        }
    }
    private var groupList: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Space.md) {
                TextField("New group name", text: $name).textFieldStyle(.roundedBorder).frame(width: 210)
                Button { add() } label: { Image(systemName: "plus") }.help("Create group").accessibilityLabel("Create group")
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Add Recommended") { addRecommended() }.disabled(recommendation != nil)
                    .help("Add automatic, fallback and manual groups to this draft")
                Spacer()
                Button { if let selection { editing = .init(id: selection, isNew: edits[selection]?["_create"] == "true") } } label: { Image(systemName: "pencil") }
                    .disabled(selection == nil).help("Edit selected group").accessibilityLabel("Edit selected group")
                Button { remove() } label: { Image(systemName: "minus") }
                    .disabled(selection == nil).help("Delete selected group in this draft").accessibilityLabel("Delete selected group")
                Button { if let selection { edits.removeValue(forKey: selection); refresh() } } label: { Image(systemName: "arrow.uturn.backward") }
                    .disabled(selection == nil || edits[selection ?? ""] == nil).help("Restore selected group inheritance").accessibilityLabel("Restore inheritance")
                Menu {
                    ForEach(edits.keys.filter { edits[$0]?["_delete"] == "true" }.sorted(), id: \.self) { key in
                        Button("Restore " + key) { edits.removeValue(forKey: key); refresh() }
                    }
                } label: { Image(systemName: "trash") }.disabled(!edits.values.contains { $0["_delete"] == "true" }).help("Restore removed subscription groups")
            }.controlSize(.small).buttonStyle(.borderless).padding(DS.Space.md)
            if let recommendation {
                Text(recommendation).font(DS.Typography.metadata).foregroundStyle(.secondary).padding(.horizontal, DS.Space.md).padding(.bottom, DS.Space.sm)
            }
            Table(groups, selection: $selection) {
                TableColumn("Group") { Text($0.name).lineLimit(1).help($0.name) }
                TableColumn("Type") { Text($0.type) }.width(95)
                TableColumn("Members") { Text($0.members.joined(separator: " → ")).lineLimit(1).help($0.members.joined(separator: ", ")) }
                TableColumn("Resources") { Text($0.providers.joined(separator: ", ")).lineLimit(1) }
                TableColumn("Source") { group in
                    Text(edits[group.name]?["_create"] == "true" ? "Local group" : edits[group.name] == nil ? "Subscription" : "Local override").foregroundStyle(.secondary)
                }.width(110)
            }.font(DS.Typography.metadata)
        }
    }
    private var routingRules: some View {
        VStack(spacing: DS.Space.md) {
            HStack {
                Picker("Type", selection: $ruleType) {
                    ForEach(["DOMAIN", "DOMAIN-SUFFIX", "DOMAIN-KEYWORD", "IP-CIDR", "PROCESS-NAME", "MATCH"], id: \.self) { Text($0).tag($0) }
                }.labelsHidden().frame(width: 155)
                if ruleType != "MATCH" { TextField("Match value", text: $ruleValue).textFieldStyle(.roundedBorder) }
                Picker("Policy", selection: $selection) {
                    Text("Choose group").tag(String?.none)
                    ForEach(groups) { Text($0.name).tag(Optional($0.name)) }
                }.labelsHidden().frame(maxWidth: 240, alignment: .leading)
                Button("Add First") {
                    guard let selection else { return }
                    let rule = ruleType == "MATCH" ? "MATCH," + selection : ruleType + "," + ruleValue + "," + selection
                    rules = rule + (rules.isEmpty ? "" : "\n" + rules)
                    ruleDocument = RuleDraftDocument(rules)
                }.disabled(selection == nil || (ruleType != "MATCH" && (ruleValue.isEmpty || ruleValue.contains(",") || ruleValue.contains("\n"))))
            }.controlSize(.small)
            HStack {
                Picker("Rule editor", selection: $sourceMode) {
                    Text("List").tag(false); Text("Source").tag(true)
                }.pickerStyle(.segmented).labelsHidden().fixedSize().frame(width: 150, alignment: .leading)
                Spacer()
                if !sourceMode {
                    Button { moveRule(-1) } label: { Image(systemName: "arrow.up") }.disabled(ruleSelection == nil).help("Move rule up")
                    Button { moveRule(1) } label: { Image(systemName: "arrow.down") }.disabled(ruleSelection == nil).help("Move rule down")
                    Button {
                        if let ruleSelection { ruleDocument.remove(id: ruleSelection); rules = ruleDocument.text; self.ruleSelection = nil }
                    } label: { Image(systemName: "minus") }.disabled(ruleSelection == nil).help("Remove rule")
                }
            }.controlSize(.small).buttonStyle(.borderless)
            if sourceMode {
                TextEditor(text: $rules).font(DS.Typography.metadata.monospaced()).scrollIndicators(.never)
            } else {
                Table(ruleDocument.rules, selection: $ruleSelection) {
                    TableColumn("Order") { row in Text(String((ruleDocument.rules.firstIndex { $0.id == row.id } ?? 0) + 1)).monospacedDigit() }.width(50)
                    TableColumn("Rule") { Text($0.rule ?? "").lineLimit(1).help($0.rule ?? "") }
                    TableColumn("Policy") { row in Text(row.rule.flatMap { RuleForm($0)?.target } ?? "Expression") }.width(130)
                }.font(DS.Typography.metadata)
                if let row = ruleDocument.rules.first(where: { $0.id == ruleSelection }) {
                    TextField("Rule expression", text: Binding(get: { row.rule ?? "" }, set: { value in
                        guard !value.contains("\n") else { return }
                        ruleDocument.replace(id: row.id, with: value); rules = ruleDocument.text
                    })).font(DS.Typography.metadata.monospaced()).textFieldStyle(.roundedBorder)
                }
            }
            Text("First match wins · MATCH ends evaluation").help("Top to bottom, first match wins. A local MATCH hides later rules. Existing comments and advanced expressions are retained.")
                .font(DS.Typography.metadata).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
        }.padding(DS.Space.lg)
        .onChange(of: sourceMode) { _, isSource in
            if isSource { rules = ruleDocument.text }
            else { ruleDocument = RuleDraftDocument(rules); ruleSelection = nil }
        }
    }
    private func moveRule(_ offset: Int) {
        if let ruleSelection { ruleDocument.move(id: ruleSelection, by: offset); rules = ruleDocument.text }
    }
    private func addRecommended() {
        do {
            let plan = try RecommendedPolicies.make(source: snapshot.source, overrides: PolicyConfiguration.encodeOverrides(edits))
            edits = try PolicyConfiguration.decodeOverrides(plan.overrides); selection = plan.manual
            recommendation = "Added " + plan.automatic + ", " + plan.fallback + " and " + plan.manual + ". Checks every 5 min; 5 sec timeout; Auto tolerance 50 ms. Fallback uses member order. Subscription rules stay intact; assign these groups in application or routing rules to use them."
            refresh()
        } catch { self.error = error.localizedDescription }
    }
    private func add() {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !groups.contains(where: { $0.name == key }), !(catalog?.nodes.contains(key) ?? false),
              !["DIRECT", "REJECT", "REJECT-DROP", "PASS", "COMPATIBLE", "GLOBAL"].contains(key), !key.contains(","), !key.contains("\n") else {
            error = "Use a unique group name without commas or line breaks."; return
        }
        editing = .init(id: key, isNew: true); name = ""
    }
    private func remove() {
        guard let selection else { return }
        if edits[selection]?["_create"] == "true" { edits.removeValue(forKey: selection) }
        else { edits[selection] = ["_delete": "true"] }
        self.selection = nil; refresh()
    }
    private func refresh() {
        do {
            groups = try PolicyConfiguration.read(PolicyConfiguration.preview(source: snapshot.source, overrides: PolicyConfiguration.encodeOverrides(edits)))
            error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func apply() {
        do {
            let text = try PolicyConfiguration.encodeOverrides(edits)
            _ = try PolicyConfiguration.apply(source: snapshot.source, overrides: text)
            applying = true; error = nil
            Task { @MainActor in
                if await PolicyGroupService.apply(text, snapshot: snapshot, localRules: rules == snapshot.localRules ? nil : rules) { dismiss() }
                else { error = AppState.shared.lastOperationError ?? "Policy changes could not be applied." }
                applying = false
            }
        } catch { self.error = error.localizedDescription }
    }
}

private struct PolicyStructureEditor: View {
    let name: String
    let isNew: Bool
    let group: PolicyConfiguration.Group?
    let inherited: PolicyConfiguration.Group?
    let override: [String: String]
    let targets: [String]
    let providers: [String]
    let save: ([String: String]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var type = "select"
    @State private var members: [String] = []
    @State private var uses: [String] = []
    @State private var member: String?
    @State private var candidate = "DIRECT"
    @State private var fields: [String: String] = [:]
    @State private var ownMembers = false
    @State private var ownProviders = false
    @State private var ownType = false
    @State private var ownFields = Set<String>()
    @State private var tab = 0
    @State private var recommendation: String?
    private var explanation: String {
        switch type {
        case "url-test": return "Selects using configured latency tests. Manual pinning remains available."
        case "fallback": return "Uses the first available member in order. Manual pinning remains available."
        case "load-balance": return "Distributes connections according to its strategy; there is no single selected exit."
        default: return "Manually choose one member or nested group."
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(name).font(DS.Typography.secondary.weight(.semibold)).lineLimit(1)
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save Draft") { store(); dismiss() }.buttonStyle(.borderedProminent)
            }.controlSize(.small).padding(DS.Space.lg)
            SettingsTabs(titles: ["Behavior", "Members", "Resources"], selection: $tab).padding(.horizontal, DS.Space.lg).padding(.bottom, DS.Space.md)
            Divider()
            if tab == 0 {
                Form {
                    Toggle("Override group type", isOn: $ownType).disabled(isNew)
                    Picker("Type", selection: $type) { ForEach(PolicyConfiguration.types, id: \.self) { Text($0).tag($0) } }.disabled(!ownType)
                    Text(explanation).font(DS.Typography.metadata).foregroundStyle(.secondary)
                    ForEach(PolicyConfiguration.editableFields(type: type) + (type == "select" ? [] : ["url"]), id: \.self) { key in
                        HStack {
                            Toggle(label(key), isOn: Binding(get: { ownFields.contains(key) }, set: { if $0 { ownFields.insert(key) } else { ownFields.remove(key) } })).toggleStyle(.checkbox)
                            Spacer()
                            if key == "lazy" || key == "strategy" {
                                Picker(key, selection: field(key)) {
                                    Text("Not set").tag("")
                                    ForEach(key == "lazy" ? ["true", "false"] : ["consistent-hashing", "round-robin", "sticky-sessions"], id: \.self) { Text($0).tag($0) }
                                }.labelsHidden().frame(width: 230).disabled(!ownFields.contains(key))
                            } else {
                                TextField(group?.fields[key] ?? "Inherited / core default", text: field(key)).labelsHidden().frame(width: 280).disabled(!ownFields.contains(key))
                            }
                        }
                    }
                }.formStyle(.grouped)
            } else if tab == 1 {
                VStack(spacing: DS.Space.md) {
                    Toggle("Override ordered members", isOn: $ownMembers).disabled(isNew)
                    HStack {
                        Picker("Member", selection: $candidate) { ForEach(targets, id: \.self) { Text($0).tag($0) } }
                        Button { if !members.contains(candidate) { members.append(candidate) } } label: { Image(systemName: "plus") }.disabled(!targets.contains(candidate) || members.contains(candidate))
                        Button { move(-1) } label: { Image(systemName: "arrow.up") }.disabled(member == nil || members.first == member)
                        Button { move(1) } label: { Image(systemName: "arrow.down") }.disabled(member == nil || members.last == member)
                        Button { members.removeAll { $0 == member }; member = nil } label: { Image(systemName: "minus") }.disabled(member == nil)
                    }.controlSize(.small).disabled(!ownMembers)
                    List(members, id: \.self, selection: $member) { value in
                        HStack { Text(value); Spacer(); if !targets.contains(value) { Text("Missing").foregroundStyle(Color.statusWarn) } }
                    }.disabled(!ownMembers)
                }.padding(DS.Space.lg)
            } else {
                VStack(alignment: .leading, spacing: DS.Space.md) {
                    Toggle("Override resource references", isOn: $ownProviders).disabled(isNew)
                    List(Array(Set(providers + uses)).sorted(), id: \.self) { resource in
                        Toggle(resource + (providers.contains(resource) ? "" : " · Missing"), isOn: Binding(get: { uses.contains(resource) }, set: { if $0 { uses.append(resource) } else { uses.removeAll { $0 == resource } } }))
                    }.disabled(!ownProviders)
                    Text("Resource members follow core filters").help("Resources supply their own members. Filters apply in the core; explicit members preserve the order shown in Members.").font(DS.Typography.metadata).foregroundStyle(.secondary)
                }.padding(DS.Space.lg)
            }
        }.frame(width: 720, height: 540).background(DS.canvas).scrollIndicators(.never, axes: [.horizontal, .vertical])
        .onAppear {
            type = override["type"] ?? group?.type ?? "select"
            members = group?.members ?? ["DIRECT"]; uses = group?.providers ?? []
            fields = group?.fields ?? [:]
            ownMembers = isNew || override["proxies"] != nil; ownProviders = isNew || override["use"] != nil
            ownType = isNew || override["type"] != nil
            ownFields = Set(override.keys.filter { PolicyConfiguration.fields.contains($0) || $0 == "url" })
        }
        .onChange(of: ownType) { _, enabled in if !enabled { type = inherited?.type ?? "select" } }
    }
    private func label(_ key: String) -> String {
        ["interval": "Interval · s", "timeout": "Timeout · ms", "tolerance": "Tolerance · ms", "url": "Probe URL"][key] ?? key.capitalized
    }
    private func field(_ key: String) -> Binding<String> { Binding(get: { fields[key] ?? "" }, set: { fields[key] = $0 }) }
    private func move(_ offset: Int) { if let member, let i = members.firstIndex(of: member), members.indices.contains(i + offset) { members.swapAt(i, i + offset) } }
    private func store() {
        var result: [String: String] = [:]
        if isNew { result["_create"] = "true" }
        if ownType { result["type"] = type }
        if ownMembers { result["proxies"] = try? PolicyConfiguration.list(members) }
        if ownProviders { result["use"] = try? PolicyConfiguration.list(uses) }
        for key in ownFields where PolicyConfiguration.editableFields(type: type).contains(key) || key == "url" { result[key] = fields[key] ?? "" }
        save(result)
    }
}
