import SwiftUI

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
    @State private var showRules = false
    @State private var showResources = false
    @State private var showScenes = false
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Diagnostics").font(DS.Typography.secondary.weight(.semibold)).fixedSize()
                Spacer()
                Menu("Inspect") {
                    Button("DNS Configuration & Query") { showDNS = true }
                    Button("Rule Sources") { showRules = true }
                    Button("Node Resources") { showResources = true }
                    Divider()
                    Button("Scenes") { showScenes = true }
                }.fixedSize()
                Button { refreshTask = Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(busy).help("Refresh diagnostics").accessibilityLabel("Refresh diagnostics")
                Button("Done") { dismiss() }.fixedSize()
            }.controlSize(.small).padding(DS.Space.lg)
            Divider()
            Table(snapshot?.rows ?? [], selection: $selection) {
                TableColumn("Area") { Text($0.id).lineLimit(1).help($0.id) }.width(min: 150, ideal: 180, max: 200)
                TableColumn("Result") { row in Text(row.status).foregroundStyle(row.attention ? Color.statusWarn : Color.primary) }.width(130)
                TableColumn("Evidence") { Text($0.detail).textSelection(.enabled).help($0.detail) }
            }.font(DS.Typography.metadata)
            if let row = snapshot?.rows.first(where: { $0.id == selection }) {
                Text(row.detail).font(DS.Typography.secondary).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(DS.Space.lg)
            }
            HStack {
                Text(error ?? snapshot.map { "Snapshot: " + $0.capturedAt.formatted(date: .omitted, time: .standard) + " · Read-only inspection; no connectivity probes." } ?? (busy ? "Reading runtime…" : "No current runtime snapshot."))
                    .foregroundStyle(error == nil ? Color.secondary : Color.statusBad)
                Spacer()
            }.font(DS.Typography.metadata).padding(DS.Space.lg)
        }.frame(minWidth: 800, minHeight: 520).background(DS.canvas)
        .task { await load() }
        .onDisappear { refreshTask?.cancel(); snapshot = nil }
        .onChange(of: controller.runtimeGeneration) { _, _ in snapshot = nil }
        .onChange(of: profiles.activeProfileRevision) { _, _ in snapshot = nil }
        .onChange(of: runtime.runtimeState) { _, _ in snapshot = nil }
        .sheet(isPresented: $showDNS) { DNSSettingsView() }
        .sheet(isPresented: $showRules) { RuleSourcesView() }
        .sheet(isPresented: $showResources) { ProxyResourcesView() }
        .sheet(isPresented: $showScenes) { ScenariosView() }
    }
    private func load() async {
        guard !busy else { return }
        busy = true; snapshot = nil; error = nil
        defer { busy = false }
        do { snapshot = try await ActivityDiagnosticsService.load() }
        catch { self.error = "Runtime diagnostics are unavailable. Wait for a stable core state and refresh." }
    }
}
