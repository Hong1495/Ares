import SwiftUI

/// Readback for a single saved provider. The operational history stays shared with diagnostics.
struct NodeProviderDetails: View {
    let name: String
    let canRead: Bool
    @EnvironmentObject private var core: ClashViewModel
    @EnvironmentObject private var controller: ClashController
    @EnvironmentObject private var app: AppState
    @State private var resource: ProxyResource?
    @State private var readbackKey: RuntimeKey?
    @State private var reading = false
    @State private var working = false
    @State private var error: String?
    @State private var message: String?
    @State private var history = false
    private struct RuntimeKey: Equatable {
        let generation: UUID
        let available: Bool
    }
    private var key: RuntimeKey {
        .init(generation: controller.runtimeGeneration, available: canRead && !core.isToggling && PolicyGroupService.canReadRuntime)
    }
    private var current: ProxyResource? { key.available && readbackKey == key ? resource : nil }
    private var canRun: Bool { key.available && !working && !reading && !app.isPerformingNetworkOperation }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            HStack(spacing: DS.Space.md) {
                if let current {
                    Label("\(current.proxies.count) members", systemImage: "point.3.connected.trianglepath.dotted").monospacedDigit()
                    Label {
                        if let date = current.updatedDate { Text("Updated \(date.formatted(date: .abbreviated, time: .shortened))") }
                        else { Text("Updated —") }
                    } icon: { Image(systemName: "clock") }
                } else { Text(status) }
                Spacer(minLength: 0)
                if key.available {
                    Button("Update") { Task { await perform(health: false) } }.disabled(!canRun || current?.canUpdate != true)
                    Button("Check Health") { Task { await perform(health: true) } }.disabled(!canRun || current?.proxies.isEmpty != false)
                    Button { Task { await refresh() } } label: { Image(systemName: "arrow.clockwise") }
                        .help("Read provider status").accessibilityLabel("Read provider status").disabled(!canRun)
                }
                Button { history = true } label: { Image(systemName: "clock.arrow.circlepath") }
                    .help("Provider activity").accessibilityLabel("Provider activity")
            }.lineLimit(1).buttonStyle(.borderless).controlSize(.small).foregroundStyle(.secondary)
            if let current, !current.proxies.isEmpty { members(current) }
            if key.available, let message = error ?? message {
                Text(message).foregroundStyle(error == nil ? Color.secondary : Color.statusBad)
            }
        }.font(DS.Typography.metadata)
            .task(id: key) { await refresh() }
            .sheet(isPresented: $history) { ResourceActivityView(kind: .nodes) }
    }

    private var status: String {
        if !canRead { return "Apply this draft to see live status." }
        if !key.available { return "Live status requires the current profile’s running core." }
        if reading { return "Reading provider status…" }
        if error != nil { return "Live status unavailable" }
        return readbackKey == key ? "Provider not loaded by the current core." : "Live status unavailable"
    }
    private func members(_ provider: ProxyResource) -> some View {
        Table(provider.proxies) {
            TableColumn("Member") { Text($0.name).lineLimit(1).help($0.name) }
            TableColumn("Type") { Text($0.type).foregroundStyle(.secondary) }.width(80)
            TableColumn("Delay") { member in
                Text(member.latest.map { $0.delay > 0 ? "\($0.delay) ms" : "Failed" } ?? "—").monospacedDigit()
            }.width(78)
            TableColumn("Measured") { member in
                Text(ProxyResource.date(member.latest?.time)?.formatted(date: .abbreviated, time: .shortened) ?? "—")
                    .foregroundStyle(.secondary).lineLimit(1)
            }.width(144)
        }.alternatingRowBackgrounds(.disabled).frame(height: 30 + CGFloat(min(provider.proxies.count, 4)) * 26)
            .help("Last measurements reported by this provider. A completed check does not mean every node is reachable.")
    }

    private func refresh() async {
        let captured = key
        resource = nil; readbackKey = nil; error = nil; message = nil
        guard captured.available else { reading = false; return }
        reading = true
        defer { if captured == key, !Task.isCancelled { reading = false } }
        do {
            let resources = try await controller.fetchProxyResources()
            guard captured == key, !Task.isCancelled else { return }
            setReadback(resources, key: captured)
        } catch {
            guard captured == key, !Task.isCancelled else { return }
            self.error = "Could not read the provider. Refresh to retry."
        }
    }
    private func perform(health: Bool) async {
        guard canRun, let current, app.beginOperation(health ? "Checking Node Provider" : "Updating Node Provider") else { return }
        let captured = key
        working = true; error = nil; message = nil
        defer { working = false; app.finishOperation(error: nil) }
        do {
            let resources = try await controller.performProxyResourceAction(name: current.name, healthCheck: health)
            guard captured == key else { return }
            setReadback(resources, key: captured)
            message = health ? "Check completed. See each member’s measurement below." : "Provider updated."
        } catch {
            guard captured == key else { return }
            resource = nil; readbackKey = nil
            self.error = "Result could not be confirmed. Refresh before retrying."
        }
    }
    private func setReadback(_ resources: [ProxyResource], key: RuntimeKey) {
        resource = resources.first { $0.name == name }
        readbackKey = key
    }
}
