import SwiftUI

struct ScenariosView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var profiles: ProfileService
    @State private var scenarios: [ManualScenario] = []
    @State private var context: ScenarioService.Context?
    @State private var name = ""
    @State private var error: String?
    @State private var review: ScenarioService.Review?
    @State private var deleting: ManualScenario?
    @State private var busy = false
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Scenes").font(DS.Typography.secondary.weight(.semibold)).fixedSize()
                Spacer()
                Button("Undo Last Switch") { review = ScenarioService.undoReview() }.disabled(ScenarioService.undoReview() == nil)
                Button("Done") { dismiss() }.fixedSize()
            }.controlSize(.small).padding(DS.Space.lg)
            HStack {
                TextField("Scene name", text: $name).textFieldStyle(.roundedBorder).accessibilityLabel("Scene name")
                Button("Save Current") { save() }.disabled(context == nil || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).fixedSize()
                Button { load() } label: { Image(systemName: "arrow.clockwise") }.help("Reload saved settings").accessibilityLabel("Reload saved settings")
            }.controlSize(.small).padding(.horizontal, DS.Space.lg).padding(.bottom, DS.Space.md)
            Text("Snapshots local rules, DNS, policy and routing overrides for this subscription. Basic settings, node selections, proxy and TUN switches stay under their existing controls.")
                .font(DS.Typography.metadata).foregroundStyle(.secondary).padding(.horizontal, DS.Space.lg).padding(.bottom, DS.Space.md)
            Divider()
            Table(scenarios) {
                TableColumn("Scene") { Text($0.name).lineLimit(1).help($0.name) }
                TableColumn("Saved") { Text($0.createdAt.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary) }.width(150)
                TableColumn("Settings") { item in
                    Text(context?.settings == item.settings ? "Matches saved" : "Different").foregroundStyle(.secondary)
                }.width(110)
                TableColumn("") { item in
                    HStack {
                        Button("Review") {
                            do { review = try ScenarioService.review(item) }
                            catch { self.error = "Select this scene’s subscription and reload before switching." }
                        }
                        Button { deleting = item } label: { Image(systemName: "trash") }.help("Delete scene").accessibilityLabel("Delete " + item.name)
                    }.buttonStyle(.borderless)
                }.width(100)
            }.font(DS.Typography.metadata)
            if let error { Text(error).font(DS.Typography.metadata).foregroundStyle(Color.statusBad).padding(DS.Space.lg) }
        }.frame(minWidth: 740, minHeight: 500).background(DS.canvas).disabled(busy).task { load() }
        .onChange(of: profiles.activeProfileRevision) { _, _ in if !busy { review = nil; load() } }
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
                Text("The subscription has changed since this scene was saved. Overrides will be validated against its current contents.").foregroundStyle(Color.statusWarn)
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
        }.font(DS.Typography.metadata).padding(DS.Space.lg).frame(width: 660, height: 380)
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
