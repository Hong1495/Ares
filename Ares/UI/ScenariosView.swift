import SwiftUI
import Combine
import SubscriptionKit

struct ScenariosView: View {
    var embedded = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var profiles: ProfileService
    @ObservedObject private var automation = SceneAutomationService.shared
    @State private var scenarios: [ManualScenario] = []
    @State private var context: ScenarioService.Context?
    @State private var selection: UUID?
    @State private var error: String?
    @State private var review: ScenarioService.Review?
    @State private var reviewError: String?
    @State private var editing: ManualScenario?
    @State private var deleting: ManualScenario?
    @State private var busy = false
    @State private var showingAutomation = false
    @State private var showingHistory = false
    @State private var creation: Creation?
    @State private var receipt: Receipt?
    private struct Creation: Identifiable { let id = UUID(); let context: ScenarioService.Context }
    private struct Receipt { let name: String; let verified: Bool; let isUndo: Bool; let hasAppRules: Bool }
    private var selectedScene: ManualScenario? { scenarios.first { $0.id == selection } }

    var body: some View {
        VStack(spacing: 0) {
            if !embedded { HStack {
                Text("Scenes").font(DS.Typography.secondary.weight(.semibold)); Spacer()
                Button("Done") { dismiss() }.controlSize(.small)
            }.padding(DS.Space.lg) }
            DSCard(padding: DS.Space.md) {
                HStack(spacing: DS.Space.md) {
                    Button(action: create) { Label("Create Scene…", systemImage: "plus") }.disabled(context == nil)
                    Spacer(minLength: 8)
                    Button { showingHistory = true } label: { Image(systemName: "clock.arrow.circlepath") }.help("History").accessibilityLabel("History")
                    if receipt == nil, ScenarioService.undoReview() != nil {
                        Button { reviewError = nil; review = ScenarioService.undoReview() } label: { Image(systemName: "arrow.uturn.backward") }
                            .help("Undo last switch").accessibilityLabel("Undo last switch")
                    }
                    Button { showingAutomation = true } label: {
                        Label(automation.enabled ? automation.paused ? "Automation Paused" : "Automation On" : "Automation Off", systemImage: "bolt.badge.clock")
                    }.help(automation.status)
                    Button { load() } label: { Image(systemName: "arrow.clockwise") }
                        .help("Refresh scenes").accessibilityLabel("Refresh scenes")
                }.controlSize(.small).buttonStyle(.borderless).font(DS.Typography.secondary)
            }.padding(.horizontal, DS.Space.lg).padding(.top, DS.Space.pageTop).padding(.bottom, DS.Space.md)
            DSCard(padding: 0, spacing: 0) {
                if scenarios.isEmpty { emptyState } else { sceneTable }
                if let scene = selectedScene, let context {
                    Divider()
                    sceneDetails(scene, context: context)
                }
            }.clipShape(RoundedRectangle(cornerRadius: DS.Radius.card)).padding(.horizontal, DS.Space.lg)
            if let error {
                Text(error).font(DS.Typography.metadata).foregroundStyle(Color.statusBad)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, DS.Space.lg).padding(.top, DS.Space.md)
            }
            if let receipt { resultBar(receipt) }
        }.padding(.bottom, DS.Space.lg)
        .frame(minWidth: embedded ? 0 : 740, minHeight: 500).background(DS.canvas).disabled(busy).task { load() }
        .toolbar { if embedded { CollectionTitleToolbar(title: "Scenes", count: context == nil ? nil : scenarios.count, unit: "Saved") } }
        .scrollIndicators(.never)
        .onChange(of: profiles.activeProfileRevision) { _, _ in if !busy { review = nil; receipt = nil; selection = nil; load() } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { refreshContext() } }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).debounce(for: .milliseconds(300), scheduler: RunLoop.main)) { _ in refreshContext() }
        .sheet(isPresented: $showingHistory) { SceneHistoryView() }
        .sheet(isPresented: $showingAutomation) { SceneAutomationView() }
        .sheet(item: $editing) { item in
            if let context { SceneEditorView(scene: item, context: context) { load() } }
        }
        .sheet(item: $creation) { request in
            CreateSceneView(context: request.context) { scene in
                load(); selection = scene.id
            }
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
    private var emptyState: some View {
        ContentUnavailableView {
            Label(context == nil ? (error == nil ? "Scenes" : "Scenes Unavailable") : "No Scenes Yet", systemImage: "square.stack.3d.up")
        } description: {
            if context != nil { Text("Save the settings you want to switch together.") }
        } actions: {
            if context != nil { Button("Create Scene…", action: create) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var sceneTable: some View {
        Table(scenarios, selection: $selection) {
            TableColumn("Scene") { Text($0.name).font(DS.Typography.secondary.weight(.medium)).lineLimit(1).help($0.name) }
            TableColumn("Scope") { scene in
                let sections = ScenarioSettings.Section.allCases.filter(scene.settings.manages)
                Text(sections.count == 1 ? sections[0].title : "\(sections.count) settings").lineLimit(1)
                    .help(sections.map(\.title).joined(separator: ", "))
            }.width(min: 105, ideal: 150)
            TableColumn("Status") { scene in Text(status(scene)).foregroundStyle(.secondary) }.width(135)
            TableColumn("Updated") { Text(($0.updatedAt ?? $0.createdAt).formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary) }.width(148)
        }.alternatingRowBackgrounds(.disabled).font(DS.Typography.metadata).frame(minHeight: 120)
    }
    private func status(_ scene: ManualScenario) -> String {
        guard let context else { return "Unavailable" }
        if (scene.validatedRevision ?? scene.sourceRevision) != context.revision { return "Review Required" }
        return scene.settings.resolved(from: context.settings) == context.settings ? "Matches Saved" : "Saved"
    }
    private func sceneDetails(_ scene: ManualScenario, context: ScenarioService.Context) -> some View {
        let target = scene.settings.resolved(from: context.settings)
        let changes = SceneChangePreview.rows(from: context.settings, to: target)
        let scope = ScenarioSettings.Section.allCases.filter(scene.settings.manages).map(\.title).joined(separator: " · ")
        return VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack(spacing: DS.Space.md) {
                Text(scene.name).font(DS.Typography.secondary.weight(.semibold)).lineLimit(1)
                Spacer()
                Button("Edit…") { editing = scene }.controlSize(.small)
                Menu {
                    Button("Delete Scene…", role: .destructive) { deleting = scene }
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Scene actions")
                Button("Review Switch…") { startReview(scene) }.buttonStyle(.borderedProminent).controlSize(.small)
            }
            HStack(spacing: DS.Space.md) {
                Label(scene.settings.manages(.mode) ? target.mode?.capitalized ?? "Current Mode" : "Keep Current Mode", systemImage: "arrow.triangle.branch")
                Label(scene.settings.manages(.selections) ? "\(target.selections?.count ?? 0) Saved Choices" : "Keep Current Choices", systemImage: "point.3.connected.trianglepath.dotted")
                Label(scene.trigger?.enabled == true ? "Automatic Match Configured" : "Manual", systemImage: "bolt.badge.clock")
            }.font(DS.Typography.metadata).foregroundStyle(.secondary).lineLimit(1)
            Text(scope.isEmpty ? "No settings selected" : scope)
                .font(DS.Typography.metadata).lineLimit(1).help(scope)
            if changes.isEmpty {
                Text("Matches the current saved settings.").font(DS.Typography.metadata).foregroundStyle(.secondary)
            } else {
                SceneChangeTable(rows: changes).frame(height: 30 + CGFloat(min(changes.count, 4)) * 26)
            }
        }.padding(DS.Space.lg)
    }
    private func resultBar(_ receipt: Receipt) -> some View {
        HStack(spacing: DS.Space.md) {
            Label(receipt.isUndo ? (receipt.verified ? "Previous settings restored" : "Previous settings saved") :
                receipt.name + (receipt.verified ? " · Core confirmed" : " · Saved for next start"),
                systemImage: receipt.verified ? "checkmark.circle" : "tray.and.arrow.down")
                .lineLimit(1)
            Spacer()
            if receipt.hasAppRules {
                Button("Check App Routes") { AppState.shared.selection = .applications }
                    .help("Applications verifies new connections against the saved routes in Rule mode.")
            }
            if ScenarioService.undoReview() != nil {
                Button("Undo…") { reviewError = nil; review = ScenarioService.undoReview() }
            }
        }.font(DS.Typography.metadata).controlSize(.small).padding(.horizontal, DS.Space.lg).padding(.top, DS.Space.md)
    }
    private func reviewView(_ item: ScenarioService.Review) -> some View {
        let changes = SceneChangePreview.rows(from: item.context.settings, to: item.target)
        return VStack(alignment: .leading, spacing: DS.Space.md) {
            Text(item.name).font(DS.Typography.secondary.weight(.semibold)).lineLimit(2)
            if item.sourceChanged {
                Text("Subscription updated. Apply with the core running to approve this scene for automation.").foregroundStyle(Color.statusWarn)
            }
            if changes.isEmpty {
                Text("No saved settings will change.").foregroundStyle(.secondary)
            } else {
                SceneChangeTable(rows: changes).frame(height: 30 + CGFloat(min(changes.count, 6)) * 26)
            }
            if changes.contains(where: { $0.after == "Remove local group definition" || $0.after == "Remove group" }) {
                Text("This switch removes local policy group definitions. Check any rules that use them.").foregroundStyle(Color.statusWarn)
            }
            if item.context.settings.localRules != item.target.localRules {
                Text("Local rules affect all subscriptions in Rule mode.").foregroundStyle(.secondary)
            }
            Text("A running core restarts to apply the scene. Undo is available until the settings or subscription change.")
                .foregroundStyle(.secondary)
            if let reviewError { Text(reviewError).foregroundStyle(Color.statusBad) }
            HStack {
                Spacer()
                Button("Cancel") { review = nil }.keyboardShortcut(.cancelAction).fixedSize()
                Button(busy ? "Applying…" : "Apply") {
                    busy = true; reviewError = nil
                    Task { @MainActor in
                        if await ScenarioService.apply(item) {
                            review = nil; load()
                            receipt = Receipt(name: item.name, verified: ScenarioService.hasVerifiedRuntime, isUndo: item.isUndo,
                                              hasAppRules: !ApplicationRouting.localRoutes(in: item.target.localRules ?? "").isEmpty)
                        } else { reviewError = AppState.shared.lastOperationError ?? "Another operation is in progress." }
                        busy = false
                    }
                }.buttonStyle(.borderedProminent).fixedSize()
            }.controlSize(.small)
        }.font(DS.Typography.metadata).padding(DS.Space.lg).frame(width: 640)
            .disabled(busy).interactiveDismissDisabled(busy)
    }
    private func load() {
        error = nil
        do { context = try ScenarioService.context(); scenarios = try ScenarioService.list() }
        catch { context = nil; scenarios = []; self.error = "Scenes could not be loaded. Select a subscription and check local storage." }
    }
    private func refreshContext() {
        guard !busy, review == nil, creation == nil, editing == nil else { return }
        if let latest = try? ScenarioService.context(), latest.revision == context?.revision { context = latest }
        else { load() }
    }
    private func create() {
        do { creation = Creation(context: try ScenarioService.context()) }
        catch { self.error = "Select a subscription before creating a scene." }
    }
    private func startReview(_ scene: ManualScenario) {
        do { reviewError = nil; review = try ScenarioService.review(scene) }
        catch { self.error = "Select this scene’s subscription and reload before switching." }
    }
}

private struct SceneChangeTable: View {
    let rows: [SceneChangePreview.Row]
    var body: some View {
        Table(rows) {
            TableColumn("Setting") { row in
                let isPath = row.section == .rules && row.subject.hasPrefix("/")
                Text(isPath ? SceneChangePreview.appName(row.subject) : row.subject).lineLimit(1)
                    .help(row.section.title + " · " + row.subject)
                    .accessibilityLabel(row.section.title + ": " + row.subject)
            }.width(min: 120, ideal: 168, max: 182)
            TableColumn("Current") { Text($0.before).lineLimit(1).help($0.before) }
            TableColumn("After Apply") { Text($0.after).lineLimit(1).help($0.after) }
        }.alternatingRowBackgrounds(.disabled).font(DS.Typography.metadata).scrollIndicators(.never)
    }
}

private struct CreateSceneView: View {
    let context: ScenarioService.Context
    let onSave: (ManualScenario) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var sections: Set<ScenarioSettings.Section> = [.rules]
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack {
                Text("Create Scene").font(DS.Typography.secondary.weight(.semibold))
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save Scene") { save() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sections.isEmpty)
            }.controlSize(.small)
            TextField("Scene name", text: $name).textFieldStyle(.roundedBorder)
            Form {
                Section("Capture from Current Settings") {
                    ForEach(ScenarioSettings.Section.allCases, id: \.self) { section in
                        Toggle(section.title, isOn: Binding(get: { sections.contains(section) }, set: { enabled in
                            if enabled { sections.insert(section) } else { sections.remove(section) }
                        })).toggleStyle(.checkbox)
                    }
                }
            }.formStyle(.grouped).scrollIndicators(.never)
            Text(error ?? "Unchecked settings stay as they are when you switch. Saving a scene leaves the network unchanged.")
                .font(DS.Typography.metadata).foregroundStyle(error == nil ? Color.secondary : Color.statusBad)
        }.padding(DS.Space.lg).frame(width: 485, height: 415).background(DS.canvas)
    }
    private func save() {
        do {
            let scene = try ScenarioService.save(name: name, sections: sections, expected: context)
            onSave(scene); dismiss()
        } catch is CancellationError { error = "The settings changed. Reopen Create Scene to capture the latest settings." }
        catch { self.error = error.localizedDescription }
    }
}

/// Edits the saved combination only; activation always uses the separate reviewed transaction.
private struct SceneEditorView: View {
    private enum SectionAction: String, CaseIterable {
        case keep = "Keep Current"
        case use = "Use Scene Settings"
        case inherit = "Restore Inheritance"
    }
    let scene: ManualScenario
    let context: ScenarioService.Context
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selected = 0
    @State private var documents = [String](repeating: "", count: 4)
    @State private var initialDocuments = [String](repeating: "", count: 4)
    @State private var actions = [SectionAction](repeating: .keep, count: 4)
    @State private var initialActions = [SectionAction](repeating: .keep, count: 4)
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
    private let settingSections: [ScenarioSettings.Section] = [.rules, .dns, .policy, .egress]
    private var pending: Bool { loaded && (name != scene.name || documents != initialDocuments || actions != initialActions || mode != (scene.settings.mode ?? "keep") || includeSelections != scene.settings.manages(.selections) || (includeSelections && choices != (scene.settings.selections ?? [:])) || trigger != (scene.trigger ?? SceneTrigger())) }
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
                        if index < 4 && actions[index] != .keep { Image(systemName: "checkmark").font(.system(size: 10)).foregroundStyle(.secondary) }
                    }.tag(index)
                }.listStyle(.sidebar).frame(width: 185)
                Divider()
                if selected == 4 { routingEditor }
                else if selected == 5 { environmentEditor }
                else { VStack(alignment: .leading, spacing: DS.Space.md) {
                    HStack {
                        Text(titles[selected]).font(DS.Typography.secondary.weight(.medium))
                        Spacer()
                        Picker("When This Scene Is Applied", selection: $actions[selected]) {
                            ForEach(SectionAction.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }.labelsHidden().controlSize(.small).fixedSize()
                    }
                    if actions[selected] == .use {
                        TextEditor(text: $documents[selected]).font(.system(size: 12, design: .monospaced))
                            .scrollContentBackground(.hidden).scrollIndicators(.never)
                            .padding(DS.Space.sm)
                            .background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.primary.opacity(0.1), lineWidth: 1))
                            .disabled(!loaded).accessibilityLabel(titles[selected] + " scene draft")
                        Text(hint).font(DS.Typography.metadata).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(actions[selected] == .keep ? "Switching to this scene leaves these settings unchanged." :
                                selected == 0 ? "Switching removes the local rules and leaves subscription rules in place." :
                                "Switching removes local overrides for this section.")
                            .font(DS.Typography.metadata).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                }.padding(DS.Space.lg) }
            }
            Divider()
            HStack {
                Text(error ?? "Save updates this scene only. Review and Apply validates the complete configuration before switching.")
                    .foregroundStyle(error == nil ? Color.secondary : Color.statusBad)
                Spacer(minLength: 0)
            }.font(DS.Typography.metadata).padding(DS.Space.lg)
        }.frame(width: 680, height: 510).background(DS.canvas).scrollIndicators(.never)
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
            HStack(spacing: 8) { Text("Proxy Mode").font(DS.Typography.secondary)
            Picker("Proxy Mode", selection: $mode) {
                Text("Keep Current").tag("keep")
                Text("Rule").tag("rule"); Text("Global").tag("global"); Text("Direct").tag("direct")
            }.labelsHidden().frame(maxWidth: 220, alignment: .leading); Spacer(minLength: 0) }
            Toggle("Include node selections", isOn: $includeSelections).toggleStyle(.switch).controlSize(.small)
            Text("Choices are validated before activation").help("Exact group and member names. Missing or unconfirmed choices fail activation and restore the previous runtime.")
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
            Text("Unlisted groups use automatic or restored choices").help("Unlisted automatic groups return to automatic selection. Unlisted manual groups retain the core’s restored/default choice. A stopped core validates choices when next started.")
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
            Text("Match all conditions · Higher priority wins").help("All conditions must match. Higher priority wins; equal-priority matches block switching. At least one condition is required. Network type and interface are not a trusted home/office identity.")
                .font(DS.Typography.metadata).foregroundStyle(.secondary)
            Text("Enable automation in Scenes").help("Automatic switching must also be enabled in Scenes → Automatic Scenes.")
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
        includeSelections = scene.settings.manages(.selections)
        choices = scene.settings.selections ?? [:]
        trigger = scene.trigger ?? SceneTrigger()
        do {
            let current = [context.settings.localRules, context.settings.dns, context.settings.policy, context.settings.egress]
            documents = try original.enumerated().map { index, value in
                let seed = value ?? (scene.settings.manages(settingSections[index]) ? nil : current[index])
                if index == 0 { return seed ?? "" }
                return try SceneOverrideDocument.render(seed ?? (index == 3 ? EgressConfiguration.empty : "{}"), section: sections[index - 1])
            }
            actions = settingSections.enumerated().map { index, section in
                scene.settings.manages(section) ? (original[index] == nil ? .inherit : .use) : .keep
            }
            initialDocuments = documents; initialActions = actions; loaded = true
        } catch { self.error = "This scene could not be opened without losing data. Its saved contents were retained." }
    }
    private func save() {
        do {
            let values: [String?] = try documents.indices.map { index in
                guard actions[index] == .use else { return nil }
                if documents[index] == initialDocuments[index], initialActions[index] == .use { return original[index] }
                if index == 0 { return documents[index] }
                do { return try SceneOverrideDocument.encode(documents[index], section: sections[index - 1]) }
                catch { selected = index; throw error }
            }
            var settings = ScenarioSettings(localRules: values[0], dns: values[1], policy: values[2], egress: values[3])
            settings.mode = mode == "keep" ? nil : mode
            settings.selections = includeSelections ? choices : nil
            let excluded = Set(settingSections.enumerated().compactMap { index, section in actions[index] == .keep ? section : nil })
            settings.keepCurrent = excluded.isEmpty ? nil : excluded
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
            Text("10 sec stable · 30 sec cooldown · Current subscription only").help("10 seconds stable · 30 seconds between attempts. No match keeps the current configuration. Failures, sleep and manual scene switches pause automation. Only the current subscription and a running core are eligible.")
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
