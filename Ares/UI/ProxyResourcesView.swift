import SwiftUI

struct ProxyResourcesView: View {
    @EnvironmentObject private var controller: ClashController
    @Environment(\.dismiss) private var dismiss
    let initialSelection: String?
    init(initialSelection: String? = nil) { self.initialSelection = initialSelection }
    @State private var showHistory = false
    @State private var resources: [ProxyResource] = []
    @State private var selection: String?
    @State private var search = ""
    @State private var memberSearch = ""
    @State private var generation: UUID?
    @State private var busy = false
    @State private var error: String?
    @State private var status: String?
    private var selected: ProxyResource? { resources.first { $0.name == selection } }
    private var filtered: [ProxyResource] {
        resources.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.vehicleType.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Node Resources").font(DS.Typography.secondary.weight(.semibold)).fixedSize()
                Text(String(resources.count)).font(DS.Typography.metadata.monospacedDigit())
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                Button("Done") { dismiss() }.controlSize(.small).fixedSize().disabled(busy)
            }.padding(DS.Space.lg)
            CollectionTools(placeholder: "Search resources", search: $search) {
                Button { showHistory = true } label: { Image(systemName: "clock.arrow.circlepath") }
                    .help("Resource activity").accessibilityLabel("Resource activity")
                Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(busy).help("Read node resources").accessibilityLabel("Read node resources")
            }
            if let error { Text(error).foregroundStyle(Color.statusBad).font(DS.Typography.metadata).padding(DS.Space.md) }
            if let status { Text(status).foregroundStyle(.secondary).font(DS.Typography.metadata).padding(.horizontal, DS.Space.lg) }
            Divider()
            Table(filtered, selection: $selection) {
                TableColumn("Resource") { Text($0.name).font(DS.Typography.metadata).lineLimit(1).truncationMode(.middle).help($0.name) }
                TableColumn("Source") { Text($0.vehicleType).font(DS.Typography.metadata).foregroundStyle(.secondary) }.width(90)
                TableColumn("Nodes") { Text(String($0.proxies.count)).font(DS.Typography.metadata.monospacedDigit()) }.width(55)
                TableColumn("Updated") { resource in
                    if let date = resource.updatedDate { Text(date, style: .relative).font(DS.Typography.metadata) }
                    else { Text("—") }
                }.width(110)
                TableColumn("") { resource in
                    HStack(spacing: 12) {
                        Button { Task { await run(resource, health: false) } } label: { Image(systemName: "arrow.down.circle") }
                            .disabled(!resource.canUpdate || busy).help("Update resource").accessibilityLabel("Update \(resource.name)")
                        Button { Task { await run(resource, health: true) } } label: { Image(systemName: "bolt") }
                            .disabled(busy || resource.proxies.isEmpty).help("Run configured health checks").accessibilityLabel("Check \(resource.name)")
                    }.buttonStyle(.borderless)
                }.width(60)
            }.frame(minHeight: 150)
            if let selected {
                Divider()
                HStack {
                    Text(selected.name).font(DS.Typography.secondary.weight(.medium)).lineLimit(1).truncationMode(.middle).help(selected.name)
                    Spacer()
                    TextField("Search resource nodes", text: $memberSearch).textFieldStyle(.roundedBorder).controlSize(.small).frame(width: 190)
                }.padding(DS.Space.md)
                Table(selected.proxies.filter { memberSearch.isEmpty || $0.name.localizedCaseInsensitiveContains(memberSearch) }) {
                    TableColumn("Node") { Text($0.name).font(DS.Typography.metadata).lineLimit(1).truncationMode(.middle).help($0.name) }
                    TableColumn("Type") { Text($0.type).font(DS.Typography.metadata).foregroundStyle(.secondary) }.width(85)
                    TableColumn("Delay") { member in
                        Text(member.latest.map { $0.delay > 0 ? "\($0.delay) ms" : "Failed" } ?? "—")
                            .font(DS.Typography.metadata.monospacedDigit())
                    }.width(85)
                    TableColumn("Measured") { member in
                        if let date = ProxyResource.date(member.latest?.time) { Text(date, style: .relative).font(DS.Typography.metadata) }
                        else { Text("—") }
                    }.width(120)
                }.frame(minHeight: 150)
            }
            Text("Provider test results · Completion does not imply availability").help("Provider history uses its configured test URL. A completed check can include failed or unmeasured nodes.")
                .font(DS.Typography.metadata).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(DS.Space.lg)
        }.frame(minWidth: 760, minHeight: 540).background(DS.canvas).interactiveDismissDisabled(busy)
        .task { search = initialSelection ?? ""; await load(); selection = initialSelection }
        .sheet(isPresented: $showHistory) { ResourceActivityView(kind: .nodes) }
        .onChange(of: controller.runtimeGeneration) { _, _ in
            resources = []; generation = nil; selection = nil; status = nil
            error = "The core changed. Refresh before working with resources."
        }
    }
    @MainActor private func load() async {
        guard !busy else { return }
        busy = true; error = nil; status = nil; resources = []; generation = nil
        let token = controller.runtimeGeneration
        defer { busy = false }
        do {
            let result = try await controller.fetchProxyResources()
            guard token == controller.runtimeGeneration else { throw CancellationError() }
            resources = result; generation = token
        } catch { resources = []; generation = nil; self.error = "Node resources could not be read from the current core." }
    }
    @MainActor private func run(_ resource: ProxyResource, health: Bool) async {
        guard generation == controller.runtimeGeneration else { error = "Refresh the current resources first."; return }
        guard !busy, AppState.shared.beginOperation(health ? "Checking Node Resource" : "Updating Node Resource") else { return }
        busy = true; error = nil; status = nil
        defer { busy = false; AppState.shared.finishOperation(error: error) }
        do {
            resources = try await controller.performProxyResourceAction(name: resource.name, healthCheck: health)
            status = health ? "Check request completed. Review measurement times and results below." : "Resource updated and read back."
            selection = resource.name
        } catch {
            resources = []; generation = nil
            self.error = "The request or its readback failed. Refresh to verify the current resource."
        }
    }
}
