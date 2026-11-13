import SwiftUI
import SubscriptionKit
import Darwin

struct EgressSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var snapshot: EgressSettingsService.Snapshot?
    @State private var edits = EgressConfiguration.Overrides()
    @State private var tab = 0
    @State private var sourceMode = false
    @State private var selected: String?
    @State private var error: String?
    @State private var busy = false
    @State private var confirmDiscard = false
    @State private var interfaces: [String] = []
    private var pending: Bool { snapshot.map { edits != (try? EgressConfiguration.decode($0.stored)) } ?? false }
    private var node: EgressConfiguration.NodeInfo? { snapshot?.inherited.nodes.first { $0.name == selected } }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Space.md) {
                Text("Routing & Listeners").font(DS.Typography.secondary.weight(.semibold)).fixedSize()
                Spacer()
                Button("Apply") { apply() }.buttonStyle(.borderedProminent).disabled(!pending || snapshot == nil)
                Button("Done") { if pending { confirmDiscard = true } else { dismiss() } }.fixedSize()
            }.controlSize(.small).padding(DS.Space.lg).disabled(busy)
            SettingsTabs(titles: ["Outbounds", "Listeners", "Forwarding"], selection: $tab)
                .padding(.horizontal, DS.Space.lg).padding(.bottom, DS.Space.md).disabled(busy)
            Divider()
            if tab == 0 { outbounds } else { inbound }
            Divider()
            HStack {
                Text(error ?? (pending ? "Unapplied changes" : "Saved configuration · Apply validates and restarts the running core."))
                    .foregroundStyle(error == nil ? Color.secondary : Color.statusBad)
                Spacer()
                if snapshot == nil { Button("Reload") { Task { await load() } }.disabled(busy) }
            }.font(DS.Typography.metadata).padding(DS.Space.lg)
        }.frame(minWidth: 740, idealWidth: 800, minHeight: 560, idealHeight: 600).background(DS.canvas).scrollIndicators(.never, axes: [.horizontal, .vertical])
        .interactiveDismissDisabled(pending || busy).task { await load() }
        .confirmationDialog("Discard unapplied routing changes?", isPresented: $confirmDiscard) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Cancel", role: .cancel) {}
        }
    }
    private var outbounds: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack {
                Toggle("Default interface", isOn: Binding(get: { edits.interface != nil }, set: { edits.interface = $0 ? snapshot?.inherited.interface ?? "" : nil }))
                    .toggleStyle(.checkbox).fixedSize()
                interfacePicker(Binding(get: { edits.interface ?? snapshot?.inherited.interface ?? "" }, set: { edits.interface = $0 }))
                    .disabled(edits.interface == nil)
                Spacer()
                Text(edits.interface == nil ? "Inherited" : "Local override").font(DS.Typography.metadata).foregroundStyle(.secondary)
            }
            let removed = Set(edits.nodes.keys).subtracting(snapshot?.inherited.nodes.map(\.name) ?? [])
            if !removed.isEmpty {
                HStack {
                    Text("Overrides reference \(removed.count) removed nodes.").foregroundStyle(Color.statusWarn)
                    Spacer()
                    Button("Remove stale overrides") { for name in removed { edits.nodes.removeValue(forKey: name) } }
                }.font(DS.Typography.metadata)
            }
            Table(snapshot?.inherited.nodes ?? [], selection: $selected) {
                TableColumn("Node") { Text($0.name).lineLimit(1).truncationMode(.middle).help($0.name) }
                TableColumn("Type") { Text($0.type).foregroundStyle(.secondary) }.width(70)
                TableColumn("Connect through") { item in Text(edits.nodes[item.name]?["dialer-proxy"] ?? item.dialer).lineLimit(1) }
                TableColumn("Interface") { item in Text(edits.nodes[item.name]?["interface-name"] ?? item.interface).lineLimit(1) }.width(95)
            }.font(DS.Typography.metadata).frame(minHeight: 160)
            if let node {
                HStack(spacing: DS.Space.md) {
                    Toggle("Connect through", isOn: enabled("dialer-proxy", inherited: node.dialer)).toggleStyle(.checkbox).fixedSize()
                    Picker("Connect through", selection: nodeValue("dialer-proxy", inherited: node.dialer)) {
                        Text("None").tag("")
                        ForEach(Array(Set((snapshot?.inherited.targets ?? []) + [node.dialer]).subtracting([node.name, ""])).sorted(), id: \.self) { Text($0).tag($0) }
                    }.labelsHidden().disabled(edits.nodes[node.name]?["dialer-proxy"] == nil)
                    Toggle("Interface", isOn: enabled("interface-name", inherited: node.interface)).toggleStyle(.checkbox).fixedSize()
                    interfacePicker(nodeValue("interface-name", inherited: node.interface), emptyLabel: "Default").disabled(edits.nodes[node.name]?["interface-name"] == nil)
                }.controlSize(.small)
                Text("\(node.name) → \((edits.nodes[node.name]?["dialer-proxy"] ?? node.dialer).isEmpty ? "No explicit dialer" : (edits.nodes[node.name]?["dialer-proxy"] ?? node.dialer))")
                    .font(DS.Typography.metadata).lineLimit(2).textSelection(.enabled)
            }
            Text("Select a node to override its dialer or interface. Unchecked fields inherit; an empty local value clears the subscription setting. Provider-managed nodes remain in their source resource.")
                .font(DS.Typography.metadata).foregroundStyle(.secondary)
        }.padding(DS.Space.lg).disabled(busy || snapshot == nil)
    }
    private func interfacePicker(_ value: Binding<String>, emptyLabel: String = "Automatic") -> some View {
        Picker("Network interface", selection: value) {
            Text(emptyLabel).tag("")
            ForEach(Array(Set(interfaces + [value.wrappedValue]).subtracting([""])).sorted(), id: \.self) { Text($0).tag($0) }
        }.labelsHidden().frame(width: 130)
    }
    private func enabled(_ key: String, inherited: String) -> Binding<Bool> {
        Binding(get: { selected.flatMap { edits.nodes[$0]?[key] } != nil }, set: { enabled in
            guard let selected else { return }
            if enabled { edits.nodes[selected, default: [:]][key] = inherited }
            else { edits.nodes[selected]?.removeValue(forKey: key); if edits.nodes[selected]?.isEmpty == true { edits.nodes.removeValue(forKey: selected) } }
        })
    }
    private func nodeValue(_ key: String, inherited: String) -> Binding<String> {
        Binding(get: { selected.flatMap { edits.nodes[$0]?[key] } ?? inherited }, set: { if let selected { edits.nodes[selected, default: [:]][key] = $0 } })
    }
    private var inbound: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack {
                Text(tab == 1 ? "HTTP · SOCKS · Mixed" : "TCP · UDP").font(DS.Typography.secondary.weight(.medium))
                Spacer()
                Toggle("Override", isOn: Binding(get: { sectionOverride != nil }, set: {
                    sectionOverride = $0 ? inheritedSection : nil
                })).toggleStyle(.switch).controlSize(.mini).fixedSize()
            }
            Text(sectionOverride == nil ? "Inherited · Read only" : "Local override · Replaces the entire section")
                .font(DS.Typography.metadata).foregroundStyle(.secondary)
            Picker("Editor", selection: $sourceMode) { Text("Form").tag(false); Text("Source").tag(true) }
                .pickerStyle(.segmented).labelsHidden().frame(width: 160)
            if !sourceMode {
                InboundForm(text: Binding(get: { sectionOverride ?? inheritedSection }, set: { sectionOverride = $0 }), section: tab == 1 ? .listeners : .tunnels, targets: snapshot?.inherited.targets ?? []).id(tab).disabled(sectionOverride == nil)
            } else {
            TextEditor(text: Binding(get: { sectionOverride ?? inheritedSection }, set: { sectionOverride = $0 }))
                .font(.system(size: 12, design: .monospaced)).scrollContentBackground(.hidden)
                .padding(DS.Space.sm).background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.primary.opacity(0.10), lineWidth: 1))
                .disabled(sectionOverride == nil).accessibilityLabel(tab == 1 ? "Listeners YAML" : "Forwarding YAML")
            HStack {
                Button("Add example") { sectionOverride = example }.disabled(sectionOverride != "[]")
                Spacer()
                Text("YAML list").font(DS.Typography.metadata).foregroundStyle(.secondary)
            }
            }
            Text(tab == 1 ? "Use an explicit IP and single port. Listener bindings are independent of Allow LAN. Use 127.0.0.1 for local access; configure users for shared access." : "Each entry maps a local address to a target through a proxy. These are fixed TCP/UDP forwards, not TUN routes.")
                .font(DS.Typography.metadata).foregroundStyle(.secondary)
        }.padding(DS.Space.lg).disabled(busy || snapshot == nil)
    }
    private var inheritedSection: String { (tab == 1 ? snapshot?.inherited.listeners : snapshot?.inherited.tunnels) ?? "[]" }
    private var sectionOverride: String? {
        get { tab == 1 ? edits.listeners : edits.tunnels }
        nonmutating set { if tab == 1 { edits.listeners = newValue } else { edits.tunnels = newValue } }
    }
    private var example: String {
        tab == 1 ? "- name: Local Proxy\n  type: mixed\n  listen: 127.0.0.1\n  port: 10808\n  udp: true\n  proxy: DIRECT" : "- network: [tcp, udp]\n  address: 127.0.0.1:10809\n  target: 127.0.0.1:8080\n  proxy: DIRECT"
    }
    @MainActor private func load() async {
        busy = true; error = nil
        defer { busy = false }
        do {
            let result = try await EgressSettingsService.load()
            edits = try EgressConfiguration.decode(result.stored); snapshot = result
            selected = result.inherited.nodes.first?.name
            var address: UnsafeMutablePointer<ifaddrs>?
            if getifaddrs(&address) == 0 {
                defer { freeifaddrs(address) }
                var cursor = address, names = Set<String>()
                while let current = cursor { names.insert(String(cString: current.pointee.ifa_name)); cursor = current.pointee.ifa_next }
                interfaces = names.sorted()
            }
        } catch { self.error = "Routing configuration could not be read. Select a subscription and try again." }
    }
    private func apply() {
        guard let snapshot else { return }
        do {
            let text = try EgressConfiguration.encode(edits)
            busy = true; error = nil
            Task { @MainActor in
                if await EgressSettingsService.apply(text, snapshot: snapshot) { await load() }
                else { error = AppState.shared.lastOperationError ?? "Another operation is in progress." }
                busy = false
            }
        } catch { self.error = "Routing settings could not be encoded." }
    }
}
