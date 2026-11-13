import SwiftUI
import SubscriptionKit

/// Advanced configuration is staged independently of the basic Settings draft.
struct DNSSettingsView: View {
    @EnvironmentObject private var controller: ClashController
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0
    @State private var sourceMode = false
    @State private var snapshot: DNSSettingsService.Snapshot?
    @State private var selection = "nameserver-policy"
    @State private var edits: [String: String] = [:]
    @State private var error: String?
    @State private var applying = false
    @State private var loading = false
    @State private var confirmDiscard = false
    private var field: DNSConfiguration.Field { DNSConfiguration.fields.first { $0.key == selection }! }
    private var pending: Bool { snapshot.map { edits != (try? DNSConfiguration.decode($0.stored)) } ?? false }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Space.lg) {
                Text("DNS").font(DS.Typography.secondary.weight(.semibold)).fixedSize()
                SettingsTabs(titles: ["Configuration", "Query"], selection: $tab).frame(width: 230)
                Spacer()
                if tab == 0 {
                    Button("Apply") { apply() }.buttonStyle(.borderedProminent).disabled(!pending || snapshot == nil)
                }
                Button("Done") { if pending { confirmDiscard = true } else { dismiss() } }.fixedSize()
            }.controlSize(.small).padding(DS.Space.lg).disabled(applying || loading)
            Divider()
            if tab == 0 { configuration } else { DNSQueryView().environmentObject(controller) }
        }
        .frame(minWidth: 740, idealWidth: 800, minHeight: 540, idealHeight: 580)
        .background(DS.canvas).scrollIndicators(.never, axes: [.horizontal, .vertical]).interactiveDismissDisabled(pending || applying)
        .task { await load() }
        .confirmationDialog("Discard unapplied DNS changes?", isPresented: $confirmDiscard) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Cancel", role: .cancel) {}
        }
    }
    private var configuration: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                List(DNSConfiguration.fields, selection: Binding<String?>(get: { selection }, set: { if let value = $0 { selection = value } })) { item in
                    HStack {
                        Text(item.title).font(DS.Typography.secondary).lineLimit(1)
                        Spacer(minLength: 4)
                        if edits[item.key] != nil { Image(systemName: "pencil").font(.system(size: 10)).foregroundStyle(.secondary) }
                    }.tag(item.key)
                }.listStyle(.sidebar).frame(width: 220)
                Divider()
                VStack(alignment: .leading, spacing: DS.Space.md) {
                    HStack {
                        Text(field.title).font(DS.Typography.secondary.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Toggle("Override", isOn: Binding(get: { edits[selection] != nil }, set: {
                            if $0 { edits[selection] = snapshot?.inherited[selection] ?? field.example }
                            else { edits.removeValue(forKey: selection) }
                        })).toggleStyle(.switch).controlSize(.mini).fixedSize()
                    }
                    Text(edits[selection] != nil ? "Local override · Applies to this subscription" : (snapshot?.sources[selection] ?? "Core default"))
                        .font(DS.Typography.metadata).foregroundStyle(.secondary)
                    if field.kind == "bool" || field.kind == "mode" || field.kind == "filterMode" {
                        Picker(field.title, selection: value) {
                            if value.wrappedValue.isEmpty { Text("Core default").tag("") }
                            ForEach(options, id: \.self) { Text($0).tag($0) }
                        }.labelsHidden().frame(maxWidth: 240, alignment: .leading).disabled(edits[selection] == nil)
                        Spacer()
                    } else {
                        Picker("Editor", selection: $sourceMode) { Text("Form").tag(false); Text("Source").tag(true) }
                            .pickerStyle(.segmented).labelsHidden().fixedSize().frame(width: 160, alignment: .leading)
                        if !sourceMode {
                            DNSValueForm(text: value, mapping: field.kind == "mapping").id(selection).disabled(edits[selection] == nil)
                        } else {
                        TextEditor(text: value).font(.system(size: 12, design: .monospaced))
                            .scrollContentBackground(.hidden).padding(DS.Space.sm)
                            .background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.primary.opacity(0.10), lineWidth: 1))
                            .disabled(edits[selection] == nil).accessibilityLabel(field.title + " YAML")
                        }
                        Text(field.kind == "mapping" ? "YAML mapping · Applying replaces this entire field." : "YAML list · Applying replaces this entire field.")
                            .font(DS.Typography.metadata).foregroundStyle(.secondary)
                    }
                    Text(field.key).font(DS.Typography.metadata.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                }.padding(DS.Space.lg).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }.disabled(applying || snapshot == nil)
            Divider()
            HStack {
                if let error { Text(error).foregroundStyle(Color.statusBad) }
                else { Text(pending ? "Unapplied changes" : "Disable Override to restore inheritance. Changes are validated before activation.").foregroundStyle(.secondary) }
                Spacer()
                if snapshot == nil { Button("Reload") { Task { await load() } }.disabled(loading) }
            }.font(DS.Typography.metadata).padding(DS.Space.lg)
        }
    }
    private var options: [String] {
        switch field.kind {
        case "bool": return ["true", "false"]
        case "mode": return ["fake-ip", "redir-host"]
        default: return ["blacklist", "whitelist", "rule"]
        }
    }
    private var value: Binding<String> {
        Binding(get: { edits[selection] ?? snapshot?.inherited[selection] ?? "" }, set: { edits[selection] = $0 })
    }
    @MainActor private func load() async {
        loading = true; error = nil
        defer { loading = false }
        do {
            let loaded = try await DNSSettingsService.load()
            edits = try DNSConfiguration.decode(loaded.stored); snapshot = loaded
        } catch { self.error = "DNS configuration could not be read. Select a subscription and try again." }
    }
    private func apply() {
        guard let snapshot else { return }
        do {
            for (key, value) in edits { try DNSConfiguration.validate(key: key, value: value) }
            let encoded = try DNSConfiguration.encode(edits)
            applying = true; error = nil
            Task { @MainActor in
                if await DNSSettingsService.apply(encoded, snapshot: snapshot) { await load() }
                else { error = AppState.shared.lastOperationError ?? "Another operation is in progress." }
                applying = false
            }
        } catch { self.error = "Invalid YAML or value. Check the overridden fields before applying." }
    }
}

private struct DNSQueryView: View {
    @EnvironmentObject private var controller: ClashController
    @EnvironmentObject private var profiles: ProfileService
    @State private var name = ""
    @State private var type = "A"
    @State private var result: DNSQueryResult?
    @State private var error: String?
    @State private var duration: Double?
    @State private var captured: Date?
    @State private var task: Task<Void, Never>?
    @State private var token = UUID()
    @State private var busy = false
    private struct Row: Identifiable {
        let id: String
        let section: String
        let record: DNSQueryResult.Record
    }
    private var rows: [Row] {
        guard let result else { return [] }
        return [("Answer", result.Answer ?? []), ("Authority", result.Authority ?? []), ("Additional", result.Additional ?? [])].flatMap { section, records in
            records.enumerated().map { Row(id: "\(section)-\($0.offset)", section: section, record: $0.element) }
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack(spacing: DS.Space.sm) {
                TextField("Domain name", text: $name).textFieldStyle(.roundedBorder).onSubmit { query() }
                    .accessibilityLabel("Domain name")
                Picker("Record type", selection: $type) { ForEach(DNSQueryResult.types, id: \.self) { Text($0).tag($0) } }
                    .labelsHidden().frame(width: 95)
                Button(busy ? "Querying…" : "Query") { query() }.fixedSize().disabled(busy || name.isEmpty)
            }.controlSize(.small)
            Text("Core DNS query · Upstream path unavailable").help("Queries the running core’s general DNS resolver. Upstream selection and proxy-host routing are not exposed by this API.")
                .font(DS.Typography.metadata).foregroundStyle(.secondary)
            if let error { Text(error).font(DS.Typography.metadata).foregroundStyle(Color.statusBad) }
            if let result {
                HStack(spacing: DS.Space.md) {
                    Text(result.statusName).font(DS.Typography.secondary.weight(.medium))
                    if result.TC { Text("Truncated").foregroundStyle(Color.statusWarn) }
                    Spacer()
                    if let duration { Text("API round trip: \(duration, specifier: "%.0f") ms") }
                    if let captured { Text(captured.formatted(date: .omitted, time: .standard)) }
                }.font(DS.Typography.metadata)
                if rows.isEmpty {
                    ContentUnavailableView(result.Status == 3 ? "Domain not found" : "No records returned", systemImage: "network")
                } else {
                    Table(rows) {
                        TableColumn("Section") { Text($0.section) }.width(70)
                        TableColumn("Name") { Text($0.record.name).lineLimit(1).help($0.record.name) }
                        TableColumn("Type") { Text($0.record.typeName) }.width(46)
                        TableColumn("TTL (s)") { Text(String($0.record.TTL)).monospacedDigit() }.width(55)
                        TableColumn("Data") { Text($0.record.data).textSelection(.enabled).help($0.record.data) }
                    }.font(DS.Typography.metadata)
                }
            } else {
                Spacer()
                Text(busy ? "Waiting for the core…" : "Enter a domain to inspect DNS records.")
                    .font(DS.Typography.secondary).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                Spacer()
            }
        }.padding(DS.Space.lg)
        .onChange(of: name) { _, _ in invalidate() }
        .onChange(of: type) { _, _ in invalidate() }
        .onChange(of: controller.runtimeGeneration) { _, _ in invalidate() }
        .onChange(of: profiles.activeProfileRevision) { _, _ in invalidate() }
        .onDisappear { invalidate() }
    }
    private func invalidate() {
        token = UUID(); task?.cancel(); task = nil; busy = false; result = nil; error = nil; duration = nil; captured = nil
    }
    private func query() {
        guard !busy else { return }
        invalidate()
        guard DNSSettingsService.canReadRuntime else { error = "Start the core with the current subscription before querying."; return }
        guard (try? DNSQueryResult.request(base: "http://127.0.0.1", name: name, type: type)) != nil else {
            error = "Enter a valid domain name or reverse DNS name."; return
        }
        busy = true
        let id = token, domain = name, recordType = type
        task = Task { @MainActor in
            let start = ContinuousClock.now
            defer { if id == token { busy = false; task = nil } }
            do {
                let response = try await controller.queryDNS(name: domain, type: recordType)
                guard id == token else { return }
                guard DNSSettingsService.canReadRuntime else { throw CancellationError() }
                result = response
                let elapsed = start.duration(to: .now).components
                duration = Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15
                captured = Date()
            } catch {
                guard id == token else { return }
                self.error = "DNS query failed. Check that DNS is enabled and its resolvers are reachable."
            }
        }
    }
}
