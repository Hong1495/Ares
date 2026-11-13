import SwiftUI
import SubscriptionKit

struct ActivityDiagnosticsView: View {
    @EnvironmentObject private var controller: ClashController
    @EnvironmentObject private var profiles: ProfileService
    @EnvironmentObject private var runtime: ClashViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var snapshot: ActivityDiagnosticsService.Snapshot?
    @State private var selection: String?
    @State private var error: String?
    @State private var busy = false
    @State private var refreshTask: Task<Void, Never>?
    @State private var showDNS = false
    @State private var showScenes = false
    @State private var destination: ActivityDiagnosticsService.Destination?
    @State private var search = ""
    @State private var attentionOnly = false
    private var rows: [ActivityDiagnosticsService.Row] {
        (snapshot?.rows ?? []).filter { (!attentionOnly || $0.attention) && (search.isEmpty || $0.id.localizedCaseInsensitiveContains(search) || $0.detail.localizedCaseInsensitiveContains(search)) }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Diagnostics").font(DS.Typography.secondary.weight(.semibold)).fixedSize()
                Spacer()
                Menu("Inspect") {
                    Button("DNS Configuration & Query") { showDNS = true }
                    Button("Rule Sources") { destination = .sources(nil) }
                    Button("Rule Sets") { destination = .rules(nil) }
                    Button("Policy Groups") { destination = .policies }
                    Button("Node Resources") { destination = .nodes(nil) }
                    Button("Resource Activity") { destination = .history }
                    Divider()
                    Button("Scenes") { showScenes = true }
                }.fixedSize()
                Button { refreshTask = Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(busy).help("Refresh diagnostics").accessibilityLabel("Refresh diagnostics")
                Button("Done") { dismiss() }.fixedSize()
            }.controlSize(.small).padding(DS.Space.lg)
            Divider()
            CollectionTools(placeholder: "Search diagnostics", search: $search) {
                Button { attentionOnly.toggle() } label: { Image(systemName: attentionOnly ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle") }
                    .help("Show items needing attention").accessibilityLabel("Show items needing attention")
                    .accessibilityValue(attentionOnly ? "On" : "Off")
            }
            Table(rows, selection: $selection) {
                TableColumn("Area") { Text($0.id).lineLimit(1).help($0.id) }.width(min: 150, ideal: 180, max: 200)
                TableColumn("Result") { row in Text(row.status).foregroundStyle(selection == row.id ? Color(nsColor: .selectedControlTextColor) : (row.attention ? Color.statusWarn : Color.primary)) }.width(130)
                TableColumn("Evidence") { Text($0.detail).lineLimit(1).truncationMode(.tail).help($0.detail) }
            }.font(DS.Typography.metadata)
            if let row = rows.first(where: { $0.id == selection }) {
                HStack(alignment: .top, spacing: DS.Space.lg) {
                    Text(row.detail).font(DS.Typography.secondary).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    if let destination = row.destination {
                        Button("Inspect") { self.destination = destination }.controlSize(.small).fixedSize()
                    }
                }.padding(DS.Space.lg)
            }
            HStack {
                Text(error ?? snapshot.map { "Updated " + $0.capturedAt.formatted(date: .omitted, time: .standard) + " · Read-only" } ?? (busy ? "Reading runtime…" : "No runtime snapshot"))
                    .help("Inspects runtime configuration without sending connectivity probes.")
                    .foregroundStyle(error == nil ? Color.secondary : Color.statusBad)
                Spacer()
            }.font(DS.Typography.metadata).padding(DS.Space.lg)
        }.frame(minWidth: 800, minHeight: 520).background(DS.canvas).scrollIndicators(.never, axes: [.horizontal, .vertical])
        .task { await load() }
        .onDisappear { refreshTask?.cancel(); snapshot = nil }
        .onChange(of: controller.runtimeGeneration) { _, _ in snapshot = nil }
        .onChange(of: profiles.activeProfileRevision) { _, _ in snapshot = nil }
        .onChange(of: runtime.runtimeState) { _, _ in snapshot = nil }
        .sheet(isPresented: $showDNS) { DNSSettingsView() }
        .sheet(item: $destination) { target in
            switch target {
            case .configuration:
                if let snapshot { DiagnosticConfigurationView(snapshot: snapshot) }
            case .policies: PolicyGroupsView()
            case .nodes(let name): ProxyResourcesView(initialSelection: name)
            case .rules(let name): RuleProvidersView(initialSelection: name)
            case .sources(let name): RuleSourcesView(provider: name)
            case .history: ResourceActivityView()
            }
        }
        .sheet(isPresented: $showScenes) { ScenariosView() }
    }
    private func load() async {
        guard !busy else { return }
        busy = true; snapshot = nil; selection = nil; error = nil
        defer { busy = false }
        do { snapshot = try await ActivityDiagnosticsService.load() }
        catch { self.error = "Runtime diagnostics are unavailable. Wait for a stable core state and refresh." }
    }
}

private struct DiagnosticConfigurationView: View {
    let snapshot: ActivityDiagnosticsService.Snapshot
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Configuration Evidence").font(DS.Typography.secondary.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }.controlSize(.small)
            }.padding(DS.Space.lg)
            SettingsTabs(titles: ["Runtime Readback", "Saved Differences"], selection: $tab).padding(.horizontal, DS.Space.lg).padding(.bottom, DS.Space.md)
            Divider()
            if tab == 0 && snapshot.audit.isEmpty {
                Text("Runtime readback unavailable for this snapshot.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if tab == 1 && snapshot.differences.isEmpty {
                Text(snapshot.rows.first { $0.id == "Saved configuration" }?.status == "Unavailable" ? "Saved comparison unavailable for this snapshot." : "No saved differences in this snapshot.")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if tab == 0 {
                SettingsRuntimeTable(rows: snapshot.audit.map { .init(id: $0.id, saved: $0.configured, running: $0.running, result: $0.status.rawValue, differs: $0.status == .different) })
            } else {
                Table(snapshot.differences) {
                    TableColumn("Field") { Text($0.path).lineLimit(1).help($0.path) }
                    TableColumn("Verified launch") { Text($0.before).textSelection(.enabled) }
                    TableColumn("Saved file") { Text($0.after).textSelection(.enabled) }
                    TableColumn("Change") { Text($0.change) }.width(85)
                }.font(DS.Typography.metadata)
            }
            Text("Captured: " + snapshot.capturedAt.formatted(date: .omitted, time: .standard) + " · Historical evidence from the selected diagnostic snapshot.")
                .font(DS.Typography.metadata).foregroundStyle(.secondary).padding(DS.Space.lg)
        }.frame(minWidth: 800, minHeight: 480).background(DS.canvas)
    }
}
