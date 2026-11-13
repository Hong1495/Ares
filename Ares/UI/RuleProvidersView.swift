import SwiftUI

struct RuleProvidersView: View {
    @EnvironmentObject private var controller: ClashController
    @Environment(\.dismiss) private var dismiss
    let initialSelection: String?
    init(initialSelection: String? = nil) { self.initialSelection = initialSelection }
    @State private var showHistory = false
    @State private var providers: [RuleProvider] = []
    @State private var search = ""
    @State private var busy = false
    @State private var loadedGeneration: UUID?
    @State private var error: String?
    private struct SourceSelection: Identifiable {
        let name: String
        var id: String { name }
    }
    @State private var sourceSelection: SourceSelection?
    @State private var inspectedProvider: String?
    @State private var relatedRules: [ClashRule] = []

    private var filtered: [RuleProvider] {
        providers.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.behavior.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Rule Sets").font(DS.Typography.secondary.weight(.semibold)).fixedSize()
                Text("\(providers.count)").font(DS.Typography.secondary.monospacedDigit())
                Spacer()
                Button("Done") { dismiss() }.controlSize(.small).fixedSize().disabled(busy)
            }.padding(DS.Space.lg)
            CollectionTools(placeholder: "Search rule sets", search: $search) {
                Button { showHistory = true } label: { Image(systemName: "clock.arrow.circlepath") }
                    .help("Resource activity").accessibilityLabel("Resource activity")
                Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
                    .help("Read rule set status").accessibilityLabel("Read rule set status")
                    .disabled(busy)
            }
            Divider()
            if let error { Text(error).font(DS.Typography.metadata).foregroundStyle(Color.statusBad).padding(DS.Space.md) }
            Table(filtered) {
                TableColumn("Name") { provider in
                    Button(provider.name) {
                        inspectedProvider = provider.name
                        relatedRules = controller.rules.filter { $0.type.lowercased().replacingOccurrences(of: "-", with: "") == "ruleset" && $0.payload == provider.name }
                    }.buttonStyle(.plain).font(DS.Typography.metadata)
                    .help("Show referencing rules")
                }
                TableColumn("Behavior") { Text($0.behavior).font(DS.Typography.metadata) }.width(90)
                TableColumn("Source") { Text($0.vehicleType).font(DS.Typography.metadata).foregroundStyle(.secondary) }.width(65)
                TableColumn("Rules") { Text(String($0.ruleCount)).font(DS.Typography.metadata.monospacedDigit()) }.width(60)
                TableColumn("Updated") { provider in
                    if let date = provider.updatedDate { Text(date, style: .relative).font(DS.Typography.metadata) }
                    else { Text("—").font(DS.Typography.metadata) }
                }.width(110)
                TableColumn("") { provider in
                    Button { Task { await update(provider) } } label: { Image(systemName: "arrow.down.circle") }
                        .buttonStyle(.borderless).disabled(busy || !provider.canUpdate)
                        .help(provider.canUpdate ? "Update this rule set" : "Inline rules come from the configuration")
                        .accessibilityLabel("Update \(provider.name)")
                }.width(30)
            }
            if let inspectedProvider {
                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    HStack {
                        Text(inspectedProvider).font(DS.Typography.secondary.weight(.medium)).lineLimit(1).truncationMode(.middle).help(inspectedProvider)
                        Spacer()
                        Button("Inspect all references") { sourceSelection = SourceSelection(name: inspectedProvider) }
                            .controlSize(.small).fixedSize()
                    }
                    if relatedRules.isEmpty {
                        Text("No top-level RULE-SET reference. Nested logical rules and sub-rules are not expanded by this API.")
                            .font(DS.Typography.metadata).foregroundStyle(.secondary)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: DS.Space.sm) {
                                ForEach(relatedRules) { rule in
                                    Text("\(rule.index + 1)   \(rule.type) → \(rule.proxy)").font(DS.Typography.metadata.monospaced())
                                }
                            }
                        }.frame(maxWidth: .infinity, maxHeight: 100, alignment: .leading)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(DS.Space.lg)
            }
        }
        .frame(minWidth: 720, minHeight: 440)
        .background(DS.canvas)
        .interactiveDismissDisabled(busy)
        .sheet(item: $sourceSelection) { RuleSourcesView(provider: $0.name) }
        .task { inspectedProvider = initialSelection; search = initialSelection ?? ""; await load() }
        .sheet(isPresented: $showHistory) { ResourceActivityView(kind: .rules) }
        .onChange(of: controller.runtimeGeneration) { _, _ in
            providers = []; relatedRules = []; inspectedProvider = nil; loadedGeneration = nil
            error = "The core changed. Refresh to read the current rule sets."
        }
    }

    @MainActor private func load() async {
        guard !busy else { return }
        busy = true; error = nil; providers = []; relatedRules = []; loadedGeneration = nil
        let generation = controller.runtimeGeneration
        defer { busy = false }
        do {
            providers = try await controller.fetchRuleProviders()
            try await controller.fetchRules()
            guard generation == controller.runtimeGeneration else { throw CancellationError() }
            loadedGeneration = generation
            if let inspectedProvider { relatedRules = controller.rules.filter { $0.type.lowercased().replacingOccurrences(of: "-", with: "") == "ruleset" && $0.payload == inspectedProvider } }
        } catch {
            providers = []
            self.error = "Rule set status could not be read from the current core."
        }
    }

    @MainActor private func update(_ provider: RuleProvider) async {
        guard loadedGeneration == controller.runtimeGeneration else {
            error = "The core changed. Refresh before updating a rule set."
            return
        }
        guard !busy, AppState.shared.beginOperation("Updating Rule Set") else { return }
        busy = true; error = nil
        defer { busy = false; AppState.shared.finishOperation(error: error) }
        do {
            providers = try await controller.updateRuleProvider(provider.name)
            if let inspectedProvider {
                relatedRules = controller.rules.filter { $0.type.lowercased().replacingOccurrences(of: "-", with: "") == "ruleset" && $0.payload == inspectedProvider }
            }
        } catch {
            providers = []; relatedRules = []; loadedGeneration = nil
            self.error = "The update or its status readback failed. Refresh to verify the current rule set."
        }
    }
}
