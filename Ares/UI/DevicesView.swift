import SwiftUI
import SubscriptionKit

struct DevicesView: View {
    @ObservedObject private var profiles = ProfileService.shared
    @ObservedObject private var controller = ClashController.shared
    @Environment(\.scenePhase) private var phase
    @State private var snapshot: ManagedWorkspaceService.Snapshot?
    @State private var draft = ManagedWorkspaceService.Document()
    @State private var selection: UUID?
    @State private var editor: DeviceAccess.Device?
    @State private var search = ""
    @State private var connections: [Connection] = []
    @State private var busy = false
    @State private var error: String?
    @State private var connectionsAvailable = false
    @State private var activityStatus = "Waiting for current connections"
    @State private var confirming = false
    private var changed: Bool { snapshot.map { draft != $0.document } ?? false }
    private var selected: DeviceAccess.Device? { draft.devices.first { $0.id == selection } }
    private var filtered: [DeviceAccess.Device] { draft.devices.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) } }
    private func observed(_ device: DeviceAccess.Device) -> [Connection] {
        // Show only connections attributed by the core to this exact managed inbound.
        guard snapshot?.document.devices.first(where: { $0.id == device.id }) == device else { return [] }
        return connections.filter { $0.metadata.inboundName == device.listenerName }
    }
    var body: some View {
        VStack(spacing: 0) {
            CollectionTools(placeholder: "Search devices", search: $search) {
                if changed { Text("Unsaved changes").font(DS.Typography.metadata).foregroundStyle(.secondary) }
                Button { newDevice() } label: { Image(systemName: "plus") }.help("Add device access")
                Button { Task { await load() } } label: { Image(systemName: "arrow.counterclockwise") }.help("Discard draft and reload")
                Button("Apply") { confirming = true }.disabled(!changed)
            }.disabled(busy || snapshot == nil)
            if let error { Text(error).font(DS.Typography.metadata).foregroundStyle(Color.statusBad).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16) }
            HSplitView {
                Table(filtered, selection: $selection) {
                    TableColumn("Device") { Text($0.name).lineLimit(1) }
                    TableColumn("Access") { Text($0.enabled ? "Enabled" : "Disabled").foregroundStyle($0.enabled ? Color.primary : .secondary) }.width(70)
                    TableColumn("Port") { Text(String($0.port)).monospacedDigit() }.width(55)
                }.frame(minWidth: 260)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if let selected {
                            HStack {
                                Text(selected.name).font(DS.Typography.secondary.weight(.medium))
                                Spacer()
                                Button("Edit") { editor = selected }
                                Button("Remove", role: .destructive) { draft.devices.removeAll { $0.id == selected.id }; selection = nil }
                            }
                            DSCard {
                                VStack(spacing: 12) {
                                    LabeledContent("Proxy address", value: selected.address)
                                    LabeledContent("Port", value: String(selected.port))
                                    LabeledContent("Username", value: selected.username)
                                    LabeledContent("Route", value: selected.target)
                                    LabeledContent("Access", value: selected.enabled ? "Enabled" : "Disabled")
                                }.textSelection(.enabled)
                            }
                            HStack {
                                Text(changed ? "Saved runtime connections" : "Current connections").font(DS.Typography.secondary.weight(.medium))
                                Spacer()
                                Text(connectionsAvailable && snapshot?.document.devices.first(where: { $0.id == selected.id }) == selected ? String(observed(selected).count) : "—").monospacedDigit()
                            }
                            ForEach(observed(selected)) { connection in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(connection.metadata.host.isEmpty ? connection.metadata.destinationIP : connection.metadata.host).lineLimit(1)
                                        Spacer()
                                        Text(ByteCountFormatter.string(fromByteCount: connection.download + connection.upload, countStyle: .binary)).monospacedDigit()
                                    }
                                    Text(connection.metadata.sourceIP + " · " + connection.chains.joined(separator: " → ")).font(DS.Typography.metadata).foregroundStyle(.secondary)
                                }
                            }
                            if observed(selected).isEmpty { Text(snapshot?.document.devices.first(where: { $0.id == selected.id }) == selected ? activityStatus : "Apply this draft to activate access").foregroundStyle(.secondary) }
                            Text("HTTP / SOCKS TCP · Authenticated proxy access").font(DS.Typography.metadata).foregroundStyle(.secondary)
                                .help("Configure this address, port and credentials on the device. Only traffic sent through this proxy is covered. Connections and byte counts describe currently open connections, not historical usage. A named access entry is not proof of physical device identity; anyone with its credentials can use it.")
                        } else {
                            Text(draft.devices.isEmpty ? "No device access configured" : "Select a device").foregroundStyle(.secondary)
                            Button("Add Device") { newDevice() }.disabled(snapshot == nil)
                        }
                    }.font(DS.Typography.secondary).padding(16).frame(maxWidth: .infinity, alignment: .leading)
                }.frame(minWidth: 330).scrollIndicators(.never)
            }.padding(.horizontal, 16).disabled(busy)
            HStack { Text("Current subscription"); Spacer(); Text("Observed proxy traffic only") }.font(DS.Typography.metadata).foregroundStyle(.secondary).padding(16)
        }.font(DS.Typography.secondary).background(DS.canvas)
        .toolbar { CollectionTitleToolbar(title: "Devices", count: draft.devices.count, unit: "configured") }
        .task(id: profiles.activeProfileRevision) { await load() }
        .task(id: phase) {
            guard phase == .active else { return }
            while !Task.isCancelled {
                await refreshConnections()
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
            }
        }
        .onChange(of: controller.runtimeGeneration) { _, _ in connections = []; connectionsAvailable = false; activityStatus = "Waiting for current runtime" }
        .onChange(of: profiles.activeProfileRevision) { _, _ in connections = []; connectionsAvailable = false; editor = nil }
        .sheet(item: $editor) { value in
            DeviceAccessEditor(value: value, targets: snapshot?.targets ?? ["DIRECT"], save: { value in
                if let index = draft.devices.firstIndex(where: { $0.id == value.id }) { draft.devices[index] = value }
                else { draft.devices.append(value) }
                selection = value.id; editor = nil
            })
        }
        .confirmationDialog("Apply device access changes?", isPresented: $confirming) {
            Button("Apply") { Task { await apply() } }
        } message: { Text("Enabled entries accept authenticated HTTP and SOCKS TCP connections on their configured local address. Applying restarts a running core and closes existing connections. Disabled or removed entries stop accepting connections after Apply.") }
    }
    private func newDevice() {
        let ports = Set(draft.devices.map(\.port))
        let port = (10810...65535).first { !ports.contains($0) } ?? 10810
        editor = .init(port: port, username: "device-" + UUID().uuidString.prefix(8), password: UUID().uuidString + UUID().uuidString)
    }
    @MainActor private func load() async {
        busy = true; snapshot = nil; connections = []; connectionsAvailable = false; selection = nil
        defer { busy = false }
        do { let value = try await ManagedWorkspaceService.load(); guard !Task.isCancelled else { return }; snapshot = value; draft = value.document; error = nil }
        catch { guard !Task.isCancelled else { return }; self.error = "Select a subscription to configure device access." }
    }
    @MainActor private func refreshConnections() async {
        guard !busy, PolicyGroupService.canReadRuntime else { connections = []; connectionsAvailable = false; activityStatus = "Core is not ready"; return }
        let generation = controller.runtimeGeneration
        do {
            let value = try await ApplicationRoutingService.connections()
            guard !Task.isCancelled, generation == controller.runtimeGeneration else { return }
            connections = value; connectionsAvailable = true; activityStatus = "No observed connections"
        } catch {
            guard !Task.isCancelled, generation == controller.runtimeGeneration else { return }
            connections = []; connectionsAvailable = false; activityStatus = "Connections unavailable"
        }
    }
    @MainActor private func apply() async {
        guard let snapshot else { return }; busy = true
        do { try await ManagedWorkspaceService.apply(draft, snapshot: snapshot); await load() }
        catch let failure as ManagedResources.Failure { error = failure.localizedDescription }
        catch { self.error = "Device access could not be applied. Check local addresses, routes and ports." }
        busy = false
    }
}

struct DeviceAccessEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var value: DeviceAccess.Device
    let targets: [String]
    let save: (DeviceAccess.Device) -> Void
    @State private var reveal = false
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Device Access").font(DS.Typography.secondary.weight(.semibold))
            DSCard {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                    GridRow { Text("Name"); TextField("Name", text: $value.name).labelsHidden() }
                    GridRow { Text("Local IP"); TextField("Local IP address", text: $value.address).labelsHidden() }
                        .help("Use this Mac's LAN address for remote access, or 127.0.0.1 for local access. Wildcard binds are not accepted.")
                    GridRow { Text("Port"); TextField("Port", value: $value.port, format: .number.grouping(.never)).labelsHidden() }
                    GridRow { Text("Username"); TextField("Username", text: $value.username).labelsHidden() }
                    GridRow {
                        Text("Password")
                        HStack {
                            if reveal { TextField("Password", text: $value.password) } else { SecureField("Password", text: $value.password) }
                            Button { reveal.toggle() } label: { Image(systemName: reveal ? "eye.slash" : "eye") }.buttonStyle(.borderless).help("Show or hide password")
                        }
                    }
                    GridRow {
                        Text("Route")
                        Picker("Route", selection: $value.target) {
                            ForEach(Array(Set(targets + ["REJECT", value.target])).sorted(), id: \.self) { Text($0).tag($0) }
                        }.labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
                    }
                    GridRow { Color.clear.gridCellUnsizedAxes([.horizontal, .vertical]); Toggle("Enable access", isOn: $value.enabled) }
                }.textFieldStyle(.roundedBorder).controlSize(.small)
            }
            if let error { Text(error).font(DS.Typography.metadata).foregroundStyle(Color.statusBad) }
            Text("Set this proxy and its credentials on the device. Access starts only after Apply.").font(DS.Typography.metadata).foregroundStyle(.secondary)
            HStack { Button("Cancel") { dismiss() }; Spacer(); Button("Save to Draft") {
                do { try DeviceAccess.validate([value]); save(value) }
                catch { self.error = error.localizedDescription }
            }.buttonStyle(.borderedProminent) }
        }.font(DS.Typography.secondary).padding(20).frame(width: 460)
    }
}
