import SwiftUI
import SubscriptionKit

struct ScenariosView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var profiles: ProfileService
    @State private var scenarios: [ManualScenario] = []
    @State private var context: ScenarioService.Context?
    @State private var name = ""
    @State private var error: String?
    @State private var review: ScenarioService.Review?
    @State private var editing: ManualScenario?
    @State private var deleting: ManualScenario?
    @State private var busy = false
    @State private var showingAutomation = false
    @State private var showingHistory = false
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Scenes").font(DS.Typography.secondary.weight(.semibold)).fixedSize()
                Spacer()
                Button { showingHistory = true } label: { Image(systemName: "clock.arrow.circlepath") }.help("Scene execution history").accessibilityLabel("Scene execution history")
                Button { showingAutomation = true } label: { Image(systemName: "bolt.badge.clock") }.help("Automatic scenes").accessibilityLabel("Automatic scenes")
                Button("Undo Last Switch") { review = ScenarioService.undoReview() }.disabled(ScenarioService.undoReview() == nil)
                Button("Done") { dismiss() }.fixedSize()
            }.controlSize(.small).padding(DS.Space.lg)
            HStack {
                TextField("Scene name", text: $name).textFieldStyle(.roundedBorder).accessibilityLabel("Scene name")
                Button("Save Current") { save() }.disabled(context == nil || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).fixedSize()
                Button { load() } label: { Image(systemName: "arrow.clockwise") }.help("Reload saved settings").accessibilityLabel("Reload saved settings")
            }.controlSize(.small).padding(.horizontal, DS.Space.lg).padding(.bottom, DS.Space.md)
            Text("Scenes combine overrides, saved node choices and proxy mode for this subscription. Proxy and TUN switches remain separate.")
                .font(DS.Typography.metadata).foregroundStyle(.secondary).padding(.horizontal, DS.Space.lg).padding(.bottom, DS.Space.md)
            Divider()
            Table(scenarios) {
                TableColumn("Scene") { Text($0.name).lineLimit(1).help($0.name) }
                TableColumn("Updated") { Text(($0.updatedAt ?? $0.createdAt).formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary) }.width(150)
                TableColumn("Settings") { item in
                    Text(context.map { item.settings.resolvingRouting(from: $0.settings) == $0.settings } == true ? "Matches saved" : "Different").foregroundStyle(.secondary)
                }.width(110)
                TableColumn("") { item in
                    HStack {
                        Button("Review") {
                            do { review = try ScenarioService.review(item) }
                            catch { self.error = "Select this scene’s subscription and reload before switching." }
                        }
                        Button { editing = item } label: { Image(systemName: "pencil") }.help("Edit scene").accessibilityLabel("Edit " + item.name)
                        Button { deleting = item } label: { Image(systemName: "trash") }.help("Delete scene").accessibilityLabel("Delete " + item.name)
                    }.buttonStyle(.borderless)
                }.width(130)
            }.font(DS.Typography.metadata)
            if let error { Text(error).font(DS.Typography.metadata).foregroundStyle(Color.statusBad).padding(DS.Space.lg) }
        }.frame(minWidth: 740, minHeight: 500).background(DS.canvas).disabled(busy).task { load() }
        .onChange(of: profiles.activeProfileRevision) { _, _ in if !busy { review = nil; load() } }
        .sheet(isPresented: $showingHistory) { SceneHistoryView() }
        .sheet(isPresented: $showingAutomation) { SceneAutomationView() }
        .sheet(item: $editing) { item in
            if let context { SceneEditorView(scene: item, context: context) { load() } }
        }
        .sheet(item: $review) { item in reviewView(item) }
        .confirmationDialog("Delete this saved scene?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete", role: .destructive) {
                if let deleting {
                    do { try ScenarioService.remove(deleting); self.deleting = nil; load() }
                    catch { self.error = "Scene could not be deleted. Reload and try again." }
                }
            }
        }
    }
    private func reviewView(_ item: ScenarioService.Review) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            Text(item.name).font(DS.Typography.secondary.weight(.semibold)).lineLimit(2)
            if item.sourceChanged {
                Text("The subscription changed. Review the affected sections below. Apply validates overrides and node choices against the current subscription; only a verified running-core switch approves this revision for automation.").foregroundStyle(Color.statusWarn)
            }
            if item.changes.isEmpty { Text("Saved overrides already match this scene. Apply still validates and activates the current configuration.").foregroundStyle(.secondary) }
            Table(item.changes) {
                TableColumn("Section") { Text($0.id) }
                TableColumn("Current") { Text($0.before) }
                TableColumn("After Apply") { Text($0.after) }
            }.frame(minHeight: 150)
            Text("Local rules are shared across subscriptions. A running core restarts; a stopped core stays stopped. Undo is available during this app session until these settings or the subscription change.")
                .foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(Color.statusBad) }
            HStack {
                Spacer()
                Button("Cancel") { review = nil }.fixedSize()
                Button(busy ? "Applying…" : "Apply") {
                    busy = true; error = nil
                    Task { @MainActor in
                        if await ScenarioService.apply(item) { review = nil; load() }
                        else { error = AppState.shared.lastOperationError ?? "Another operation is in progress." }
                        busy = false
                    }
                }.buttonStyle(.borderedProminent).fixedSize()
            }.controlSize(.small)
        }.font(DS.Typography.metadata).padding(DS.Space.lg).frame(width: 700, height: 440)
            .disabled(busy).interactiveDismissDisabled(busy)
    }
    private func load() {
        error = nil
        do { context = try ScenarioService.context(); scenarios = try ScenarioService.list() }
        catch { context = nil; scenarios = []; self.error = "Scenes could not be loaded. Select a subscription and check local storage." }
    }
    private func save() {
        guard let context else { return }
        do { try ScenarioService.save(name: name, expected: context); name = ""; load() }
        catch { self.error = "Scene could not be saved. Use a unique name (1–80 characters) and reload if settings changed." }
    }
}

/// Edits the saved combination only; activation always uses the separate reviewed transaction.
private struct SceneEditorView: View {
    let scene: ManualScenario
    let context: ScenarioService.Context
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selected = 0
    @State private var documents = [String](repeating: "", count: 4)
    @State private var initialDocuments = [String](repeating: "", count: 4)
    @State private var overrides = [Bool](repeating: false, count: 4)
    @State private var initialOverrides = [Bool](repeating: false, count: 4)
    @State private var error: String?
    @State private var loaded = false
    @State private var discard = false
    @State private var mode = "keep"
    @State private var includeSelections = false
    @State private var choices: [String: String] = [:]
    @State private var groupName = ""
    @State private var nodeName = ""
    @State private var trigger = SceneTrigger()
    @State private var catalog: SceneCatalogService.Catalog?
    @State private var catalogError: String?
    private let titles = ["Local Rules", "DNS", "Policy Groups", "Routing & Listeners", "Mode & Nodes", "Environment"]
    private let sections: [SceneOverrideDocument.Section] = [.dns, .policy, .routing]
    private var pending: Bool { loaded && (name != scene.name || documents != initialDocuments || overrides != initialOverrides || mode != (scene.settings.mode ?? "keep") || includeSelections != (scene.settings.selections != nil) || (includeSelections && choices != (scene.settings.selections ?? [:])) || trigger != (scene.trigger ?? SceneTrigger())) }
    private var original: [String?] { [scene.settings.localRules, scene.settings.dns, scene.settings.policy, scene.settings.egress] }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Space.md) {
                Text("Edit Scene").font(DS.Typography.secondary.weight(.semibold)).fixedSize()
                TextField("Scene name", text: $name).textFieldStyle(.roundedBorder).accessibilityLabel("Scene name")
                Button("Cancel") { if pending { discard = true } else { dismiss() } }.fixedSize()
                Button("Save") { save() }.buttonStyle(.borderedProminent).disabled(!pending).fixedSize()
            }.controlSize(.small).padding(DS.Space.lg)
            Divider()
            HStack(spacing: 0) {
                List(titles.indices, id: \.self, selection: Binding<Int?>(get: { selected }, set: { if let value = $0 { selected = value } })) { index in
                    HStack {
                        Text(titles[index]).lineLimit(1)
                        Spacer(minLength: 4)
                        if index < 4 && overrides[index] { Image(systemName: "pencil").font(.system(size: 10)).foregroundStyle(.secondary) }
                    }.tag(index)
                }.listStyle(.sidebar).frame(width: 185)
                Divider()
                if selected == 4 { routingEditor }
                else if selected == 5 { environmentEditor }
                else { VStack(alignment: .leading, spacing: DS.Space.md) {
                    HStack {
                        Text(titles[selected]).font(DS.Typography.secondary.weight(.medium))
                        Spacer()
                        Toggle("Override", isOn: $overrides[selected]).toggleStyle(.switch).controlSize(.mini).fixedSize()
                    }
                    Text(overrides[selected] ? "Saved with this scene" : "Restore inheritance when this scene is applied")
                        .font(DS.Typography.metadata).foregroundStyle(.secondary)
                    TextEditor(text: $documents[selected]).font(.system(size: 12, design: .monospaced))
                        .scrollContentBackground(.hidden).scrollIndicators(.never)
                        .padding(DS.Space.sm)
                        .background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.primary.opacity(0.1), lineWidth: 1))
                        .disabled(!overrides[selected] || !loaded).accessibilityLabel(titles[selected] + " scene draft")
                    Text(hint).font(DS.Typography.metadata).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(DS.Space.lg) }
            }
            Divider()
            HStack {
                Text(error ?? "Save updates this scene only. Review and Apply validates the complete configuration before switching.")
                    .foregroundStyle(error == nil ? Color.secondary : Color.statusBad)
                Spacer(minLength: 0)
            }.font(DS.Typography.metadata).padding(DS.Space.lg)
        }.frame(width: 760, height: 520).background(DS.canvas).scrollIndicators(.never)
            .interactiveDismissDisabled(pending).onAppear { load() }
            .task { await loadCatalog() }
            .confirmationDialog("Discard scene edits?", isPresented: $discard) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            }
    }
    private func loadCatalog() async {
        do {
            let result = try await SceneCatalogService.load()
            guard result.revision == context.revision else { throw CancellationError() }
            catalog = result; catalogError = nil; groupName = ""; nodeName = ""
        } catch { catalog = nil; catalogError = "Members unavailable. Reload after the subscription or core is ready." }
    }
    private var routingEditor: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            Picker("Proxy Mode", selection: $mode) {
                Text("Keep Current").tag("keep")
                Text("Rule").tag("rule"); Text("Global").tag("global"); Text("Direct").tag("direct")
            }.frame(maxWidth: 320)
            Toggle("Include node selections", isOn: $includeSelections).toggleStyle(.switch).controlSize(.small)
            Text("Exact group and member names. Missing or unconfirmed choices fail activation and restore the previous runtime.")
                .font(DS.Typography.metadata).foregroundStyle(.secondary)
            HStack {
                Picker("Group", selection: $groupName) {
                    Text("Choose group").tag("")
                    ForEach(catalog?.groups ?? []) { Text($0.name).tag($0.name) }
                }.labelsHidden().accessibilityLabel("Scene selection group")
                Picker("Node", selection: $nodeName) {
                    Text("Choose member").tag("")
                    ForEach(catalog?.groups.first(where: { $0.name == groupName })?.all ?? [], id: \.self) { Text($0).tag($0) }
                }.labelsHidden().accessibilityLabel("Scene selection member")
                Button { choices[groupName] = nodeName; groupName = ""; nodeName = "" } label: { Image(systemName: "plus") }
                    .disabled(groupName.isEmpty || nodeName.isEmpty).accessibilityLabel("Add node selection")
            }.controlSize(.small).disabled(!includeSelections || catalog == nil)
                .onChange(of: groupName) { _, _ in nodeName = "" }
            HStack {
                Text(catalogError ?? (catalog?.live == true ? "Current core members" : "Subscription members · Provider members require a running core"))
                    .font(DS.Typography.metadata).foregroundStyle(.secondary)
                Spacer()
                Button { Task { await loadCatalog() } } label: { Image(systemName: "arrow.clockwise") }.help("Reload members")
            }
            List(choices.keys.sorted(), id: \.self) { key in
                HStack {
                    VStack(alignment: .leading) { Text(key); Text(choices[key] ?? "").foregroundStyle(.secondary)
                        if catalog?.groups.first(where: { $0.name == key })?.all.contains(choices[key] ?? "") != true {
                            Text(catalog?.live == true ? "Missing from current core" : "Not in subscription snapshot").foregroundStyle(Color.statusWarn)
                        } }.lineLimit(1).help(key + " → " + (choices[key] ?? ""))
                    Spacer()
                    Button { choices.removeValue(forKey: key) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless).accessibilityLabel("Remove " + key)
                }
            }.disabled(!includeSelections)
            Button("Use Current Saved Choices") { choices = context.settings.selections ?? [:]; includeSelections = true }
            Text("Unlisted automatic groups return to automatic selection. Unlisted manual groups retain the core’s restored/default choice. A stopped core validates choices when next started.")
                .font(DS.Typography.metadata).foregroundStyle(.secondary)
        }.font(DS.Typography.secondary).padding(DS.Space.lg)
    }
    private var environmentEditor: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            Toggle("Match this scene automatically", isOn: $trigger.enabled).toggleStyle(.switch).controlSize(.small)
            Picker("Network", selection: $trigger.kind) {
                Text("Any").tag("any"); Text("Wi-Fi").tag("wifi"); Text("Ethernet").tag("wired"); Text("Cellular").tag("cellular")
            }
            TextField("Interface (optional, e.g. en0)", text: $trigger.interface).textFieldStyle(.roundedBorder)
            Picker("Metered", selection: $trigger.cost) { Text("Any").tag("any"); Text("Yes").tag("yes"); Text("No").tag("no") }
            Picker("Low Data Mode", selection: $trigger.constrained) { Text("Any").tag("any"); Text("Yes").tag("yes"); Text("No").tag("no") }
            Stepper("Priority: \(trigger.priority)", value: $trigger.priority, in: -100...100)
            Text("All conditions must match. Higher priority wins; equal-priority matches block switching. At least one condition is required. Network type and interface are not a trusted home/office identity.")
                .font(DS.Typography.metadata).foregroundStyle(.secondary)
            Text("Automatic switching must also be enabled in Scenes → Automatic Scenes.")
                .font(DS.Typography.metadata).foregroundStyle(.secondary)
            Spacer()
        }.font(DS.Typography.secondary).controlSize(.small).padding(DS.Space.lg)
    }
    private var hint: String {
        switch selected {
        case 0: return "One rule per line, in match order. Local rules are shared across subscriptions."
        case 1: return "YAML mapping of advanced DNS fields, including hosts. Omitted fields inherit."
        case 2: return "YAML mapping: group name → parameters. Group types and references are checked on Apply."
        default: return "YAML keys: nodes, interface, listeners, tunnels. Listener credentials remain in private scene storage."
        }
    }
    private func load() {
        name = scene.name
        mode = scene.settings.mode ?? "keep"
        includeSelections = scene.settings.selections != nil
        choices = scene.settings.selections ?? [:]
        trigger = scene.trigger ?? SceneTrigger()
        do {
            documents = try original.enumerated().map { index, value in
                if index == 0 { return value ?? "" }
                return try SceneOverrideDocument.render(value ?? (index == 3 ? EgressConfiguration.empty : "{}"), section: sections[index - 1])
            }
            overrides = original.map { $0 != nil }
            initialDocuments = documents; initialOverrides = overrides; loaded = true
        } catch { self.error = "This scene could not be opened without losing data. Its saved contents were retained." }
    }
    private func save() {
        do {
            let values: [String?] = try documents.indices.map { index in
                guard overrides[index] else { return nil }
                if documents[index] == initialDocuments[index], initialOverrides[index] { return original[index] }
                if index == 0 { return documents[index] }
                do { return try SceneOverrideDocument.encode(documents[index], section: sections[index - 1]) }
                catch { selected = index; throw error }
            }
            var settings = ScenarioSettings(localRules: values[0], dns: values[1], policy: values[2], egress: values[3])
            settings.mode = mode == "keep" ? nil : mode
            settings.selections = includeSelections ? choices : nil
            try trigger.validate()
            try ScenarioService.update(scene, name: name, settings: settings, expected: context, trigger: trigger)
            onSave(); dismiss()
        } catch {
            self.error = "Could not save. Check the draft and unique scene name. If settings, subscription or scene changed, reopen the editor."
        }
    }
}

private struct SceneAutomationView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var service = SceneAutomationService.shared
    @State private var confirmEnable = false
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack {
                Text("Automatic Scenes").font(DS.Typography.secondary.weight(.semibold))
                Spacer()
                Toggle("Enabled", isOn: Binding(get: { service.enabled }, set: {
                    if $0 { confirmEnable = true } else { service.setEnabled(false) }
                })).toggleStyle(.switch).controlSize(.small)
                Button(service.paused ? "Resume" : "Pause") {
                    if service.paused { service.resume() } else { service.pause() }
                }.disabled(!service.enabled)
                Button("Done") { dismiss() }
            }.controlSize(.small)
            Text(service.status).font(DS.Typography.secondary)
            Text("Network: \(service.environment.kind) · Interface: \(service.environment.interface.isEmpty ? "Unknown" : service.environment.interface) · Metered: \(service.environment.expensive ? "Yes" : "No") · Low Data: \(service.environment.constrained ? "Yes" : "No")")
                .font(DS.Typography.metadata).foregroundStyle(.secondary).textSelection(.enabled)
            Table(service.rows) {
                TableColumn("Scene") { Text($0.name).lineLimit(1).help($0.name) }
                TableColumn("Priority") { Text(String($0.priority)).monospacedDigit() }.width(65)
                TableColumn("Match") { Text($0.reason) }
            }.font(DS.Typography.metadata)
            Text("10 seconds stable · 30 seconds between attempts. No match keeps the current configuration. Failures, sleep and manual scene switches pause automation. Only the current subscription and a running core are eligible.")
                .font(DS.Typography.metadata).foregroundStyle(.secondary)
        }.padding(DS.Space.lg).frame(width: 760, height: 430).background(DS.canvas).scrollIndicators(.never)
            .task { service.start() }
            .confirmationDialog("Enable automatic scene switching?", isPresented: $confirmEnable) {
                Button("Enable") { service.setEnabled(true) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Matching scenes can restart the running core and change rules, DNS, node selections and proxy mode. System proxy and TUN switches stay unchanged.")
            }
    }
}

private struct SceneHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [SceneExecution] = []
    @State private var selection: UUID?
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack {
                Text("Scene History").font(DS.Typography.secondary.weight(.semibold))
                Spacer()
                Button { load() } label: { Image(systemName: "arrow.clockwise") }.help("Reload history")
                Button("Done") { dismiss() }
            }.controlSize(.small)
            Table(entries, selection: $selection) {
                TableColumn("Time") { Text($0.date.formatted(date: .abbreviated, time: .standard)) }.width(160)
                TableColumn("Scene") { Text($0.name).lineLimit(1).help($0.name) }
                TableColumn("Trigger") { Text($0.automatic ? "Automatic" : "Manual") }.width(80)
                TableColumn("Result") { Text($0.result).lineLimit(2).help($0.result) }
            }.font(DS.Typography.metadata)
            if let item = entries.first(where: { $0.id == selection }) {
                Text(item.sections.isEmpty ? "No saved-setting differences" : "Changed sections: " + item.sections.joined(separator: " · "))
                    .font(DS.Typography.metadata).textSelection(.enabled)
            }
            Text(error ?? "Last 100 attempts · Configuration values and network identifiers are not recorded.")
                .font(DS.Typography.metadata).foregroundStyle(error == nil ? Color.secondary : Color.statusBad)
        }.padding(DS.Space.lg).frame(width: 800, height: 440).background(DS.canvas).scrollIndicators(.never).task { load() }
    }
    private func load() {
        do { entries = try ScenarioService.history(); error = nil }
        catch { entries = []; self.error = "History could not be read. Existing records were retained." }
    }
}
