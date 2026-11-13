import SwiftUI
import SubscriptionKit

struct DNSValueForm: View {
    @Binding var text: String
    let mapping: Bool
    @State private var selection: String?
    @State private var key = ""
    @State private var values = ""
    @State private var listValue = true
    @State private var error: String?
    private var rows: [NetworkFormDocument.Entry]? {
        if mapping { return try? NetworkFormDocument.entries(text) }
        return try? NetworkFormDocument.strings(text).enumerated().map { .init(key: String($0.offset), values: [$0.element], isList: false) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            if let rows {
                Table(rows, selection: $selection) {
                    TableColumn(mapping ? "Domain / Pattern" : "Order") { Text(mapping ? $0.key : String((Int($0.key) ?? 0) + 1)).lineLimit(1) }.width(min: 70, ideal: 130)
                    TableColumn("Value") { Text($0.values.joined(separator: ", ")).lineLimit(1).help($0.values.joined(separator: ", ")) }
                }.font(DS.Typography.metadata)
                if mapping { TextField("Domain or policy pattern", text: $key).textFieldStyle(.roundedBorder) }
                TextField(mapping ? "Values, one per line" : "Resolver or filter", text: $values, axis: .vertical)
                    .lineLimit(1...4).textFieldStyle(.roundedBorder)
                HStack {
                    if mapping { Toggle("List value", isOn: $listValue).toggleStyle(.checkbox) }
                    Spacer()
                    Button("New") { selection = nil; key = ""; values = ""; error = nil }
                    Button("Remove") { mutate(rows.filter { $0.key != selection }) }.disabled(selection == nil)
                    if !mapping {
                        Button { move(-1, rows: rows) } label: { Image(systemName: "arrow.up") }.disabled(selection == nil)
                        Button { move(1, rows: rows) } label: { Image(systemName: "arrow.down") }.disabled(selection == nil)
                    }
                    Button(selection == nil ? "Add" : "Save Row") { save(rows) }.disabled(values.isEmpty || (mapping && key.isEmpty))
                }.controlSize(.small)
                if let error { Text(error).foregroundStyle(Color.statusBad).font(DS.Typography.metadata) }
            } else {
                Text("Advanced value · Edit in Source").foregroundStyle(.secondary).font(DS.Typography.secondary)
                Spacer()
            }
        }
        .onChange(of: selection) { _, selected in
            guard let row = rows?.first(where: { $0.key == selected }) else { return }
            key = row.key; values = row.values.joined(separator: "\n"); listValue = row.isList
        }
    }
    private func save(_ rows: [NetworkFormDocument.Entry]) {
        var updated = rows
        let row = NetworkFormDocument.Entry(key: mapping ? key : selection ?? String(rows.count), values: mapping && listValue ? values.components(separatedBy: .newlines).filter { !$0.isEmpty } : [values], isList: mapping && listValue)
        if let index = rows.firstIndex(where: { $0.key == selection }) { updated[index] = row } else { updated.append(row) }
        mutate(updated)
    }
    private func move(_ delta: Int, rows: [NetworkFormDocument.Entry]) {
        guard let index = rows.firstIndex(where: { $0.key == selection }), rows.indices.contains(index + delta) else { return }
        var changed = rows; changed.swapAt(index, index + delta); mutate(changed)
    }
    private func mutate(_ rows: [NetworkFormDocument.Entry]) {
        do {
            text = mapping ? try NetworkFormDocument.entries(rows) : try NetworkFormDocument.strings(rows.flatMap(\.values))
            selection = nil; key = ""; values = ""; error = nil
        } catch { self.error = error.localizedDescription }
    }
}

struct InboundForm: View {
    @Binding var text: String
    let section: NetworkFormDocument.Section
    let targets: [String]
    @State private var selected: Int?
    @State private var editor: Draft?
    @State private var error: String?
    private struct Draft: Identifiable { let id = UUID(); let index: Int?; let fields: [String: String] }
    private var rows: [NetworkFormDocument.Record] { (try? NetworkFormDocument.records(text, section: section)) ?? [] }
    var body: some View {
        VStack(spacing: DS.Space.md) {
            HStack {
                Text("\(rows.count) Entries").font(DS.Typography.metadata).foregroundStyle(.secondary)
                Spacer()
                Button { editor = Draft(index: nil, fields: section == .listeners ? ["name": "Local Proxy", "type": "mixed", "listen": "127.0.0.1", "port": "10808", "udp": "true", "proxy": "DIRECT"] : ["network": "tcp,udp", "address": "127.0.0.1:10809", "target": "127.0.0.1:8080", "proxy": "DIRECT"]) } label: { Image(systemName: "plus") }.help("Add entry")
                Button { if let row = rows.first(where: { $0.id == selected }), let fields = row.fields { editor = Draft(index: row.id, fields: fields) } } label: { Image(systemName: "pencil") }.disabled(rows.first { $0.id == selected }?.fields == nil).help("Edit entry")
                Button {
                    guard let selected else { return }
                    do { text = try NetworkFormDocument.removeRecord(text, index: selected); self.selected = nil }
                    catch { self.error = error.localizedDescription }
                } label: { Image(systemName: "minus") }.disabled(selected == nil).help("Remove entry")
            }.buttonStyle(.borderless).controlSize(.small)
            Table(rows, selection: $selected) {
                TableColumn("Entry") { Text($0.title).lineLimit(1).help($0.title) }
                TableColumn("Protocol") { Text($0.fields?[section == .listeners ? "type" : "network"] ?? "Advanced") }.width(100)
                TableColumn("Listen") { Text(section == .listeners ? ($0.fields?["listen"] ?? "") + ":" + ($0.fields?["port"] ?? "") : $0.fields?["address"] ?? "—") }
                TableColumn("Route") { Text($0.fields?[section == .listeners ? "proxy" : "target"] ?? "—").lineLimit(1) }
            }.font(DS.Typography.metadata)
            if (try? NetworkFormDocument.records(text, section: section)) == nil {
                Text("This section could not be projected. Use Source to inspect it.").font(DS.Typography.metadata).foregroundStyle(Color.statusWarn)
            }
            if let error { Text(error).foregroundStyle(Color.statusBad).font(DS.Typography.metadata) }
        }
        .sheet(item: $editor) { draft in
            InboundEntryEditor(section: section, initial: draft.fields, targets: targets) { fields in
                text = try NetworkFormDocument.saveRecord(text, section: section, index: draft.index, fields: fields)
                selected = nil
            }
        }
    }
}
private struct InboundEntryEditor: View {
    let section: NetworkFormDocument.Section
    let initial: [String: String]
    let targets: [String]
    let save: ([String: String]) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var fields: [String: String] = [:]
    @State private var error: String?
    var body: some View {
        VStack(spacing: DS.Space.md) {
            HStack {
                Text(section == .listeners ? "Listener" : "Forwarding").font(DS.Typography.secondary.weight(.semibold))
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save Draft") { do { try save(fields); dismiss() } catch { self.error = error.localizedDescription } }.buttonStyle(.borderedProminent)
            }.controlSize(.small)
            Form {
                if section == .listeners {
                    TextField("Name", text: binding("name"))
                    Picker("Protocol", selection: binding("type")) { ForEach(["http", "socks", "mixed"], id: \.self) { Text($0).tag($0) } }
                    TextField("Listen IP", text: binding("listen"))
                    TextField("Port", text: binding("port"))
                    if fields["type"] != "http" {
                        Toggle("UDP", isOn: Binding(get: { fields["udp"] != "false" }, set: { fields["udp"] = $0 ? "true" : "false" }))
                    }
                } else {
                    Picker("Protocol", selection: binding("network")) { Text("TCP").tag("tcp"); Text("UDP").tag("udp"); Text("TCP + UDP").tag("tcp,udp") }
                    TextField("Listen IP:port", text: binding("address"))
                    TextField("Target host:port", text: binding("target"))
                }
                Picker("Route", selection: binding("proxy")) {
                    Text("Follow rules").tag("")
                    ForEach(Array(Set(targets + [fields["proxy"] ?? "", "DIRECT"]).subtracting([""])).sorted(), id: \.self) { Text($0).tag($0) }
                }
            }.formStyle(.grouped)
            if let error { Text(error).foregroundStyle(Color.statusBad).font(DS.Typography.metadata) }
            Text("Unknown fields, authentication and TLS settings are preserved. Use Source to edit advanced options.")
                .font(DS.Typography.metadata).foregroundStyle(.secondary)
        }.padding(DS.Space.lg).frame(width: 600, height: 460).background(DS.canvas).scrollIndicators(.never)
        .onAppear { fields = initial }
    }
    private func binding(_ key: String) -> Binding<String> { Binding(get: { fields[key] ?? "" }, set: { fields[key] = $0 }) }
}
