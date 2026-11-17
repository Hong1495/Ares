import SwiftUI

/// Value-only rows keep the native table shared with the isolated design preview.
struct ProxyTableRow: Identifiable {
    let id: String
    let type: String
    let delay: Int?
    var selected = false
    var active = false
    var testing = false
}

struct ProxyWorkspaceTable: View {
    struct GroupRow: Identifiable {
        let id: String
        let type: String
        let current: String?
        let count: Int
        var matches = true
    }
    let groups: [GroupRow]
    @Binding var selectedGroup: String?
    @Binding var focusedNode: String?
    let rows: [ProxyTableRow]
    let search: String
    var canSelect = true
    var canTest = true
    var automatic = false
    var pinned = false
    var busy = false
    let onSelect: (String) -> Void
    let onTest: (String) -> Void
    let onResume: () -> Void

    private var group: GroupRow? { groups.first { $0.id == selectedGroup } ?? groups.first }
    private var groupSelection: Binding<String?> {
        Binding(get: { group?.id }, set: { value in
            // List can clear its selection while refreshing. Keep a valid group open.
            if let value, groups.contains(where: { $0.id == value }) { selectedGroup = value }
        })
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    Text("Groups").font(DS.Typography.secondary.weight(.medium))
                    Spacer()
                    Text(String(groups.count)).font(DS.Typography.metadata.monospacedDigit()).foregroundStyle(.secondary)
                }.padding(.horizontal, 12).frame(height: 36)
                Divider()
                List(groups, selection: groupSelection) { item in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Text(item.id).lineLimit(1).truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(String(item.count)).monospacedDigit().foregroundStyle(.secondary)
                        }.font(DS.Typography.secondary)
                        HStack(spacing: 6) {
                            Text(Self.typeLabel(item.type))
                            if let current = item.current { Text("·"); Text(current).lineLimit(1).truncationMode(.middle) }
                        }.font(DS.Typography.metadata).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 5)
                    .opacity(item.matches || search.isEmpty ? 1 : 0.5)
                    .tag(item.id)
                    .help(item.id + " · " + Self.typeLabel(item.type) + " · " + (item.type == "LoadBalance" ? "Per-connection balancing" : item.current ?? "No current node"))
                }.listStyle(.inset).scrollContentBackground(.hidden)
            }.frame(minWidth: 160, idealWidth: 190, maxWidth: 220)

            VStack(spacing: 0) {
                if let group {
                    HStack(spacing: 10) {
                        Text(group.id).font(DS.Typography.secondary.weight(.medium)).lineLimit(1).truncationMode(.middle).help(group.id)
                        if group.id.caseInsensitiveCompare(Self.typeLabel(group.type)) != .orderedSame {
                            Text(Self.typeLabel(group.type)).font(DS.Typography.metadata).foregroundStyle(.secondary).fixedSize()
                        }
                        Spacer(minLength: 8)
                        if automatic {
                            Button(action: onResume) {
                                Label(pinned ? "Resume Auto" : "Auto", systemImage: pinned ? "arrow.triangle.2.circlepath" : "checkmark")
                            }.buttonStyle(.borderless).controlSize(.small)
                                .disabled(!pinned || busy)
                                .help("Let this group choose nodes automatically")
                        }
                    }.padding(.horizontal, 12).frame(height: 36)
                    Divider()
                    nodeTable
                    Divider()
                    HStack(spacing: 6) {
                        Text(String(rows.count)).monospacedDigit()
                        Text(search.isEmpty ? (rows.count == 1 ? "member" : "members") : (rows.count == 1 ? "match" : "matches"))
                        Spacer(minLength: 8)
                        Text(group.type == "LoadBalance" ? "Per-connection balancing" : automatic ? (pinned ? "Pinned" : "Automatic") : "Manual selection")
                    }.font(DS.Typography.metadata).foregroundStyle(.secondary)
                        .padding(.horizontal, 12).frame(height: 30)
                } else {
                    ContentUnavailableView("Select a group", systemImage: "list.bullet")
                }
            }.frame(minWidth: 450, maxWidth: .infinity, maxHeight: .infinity)
        }
        .font(DS.Typography.secondary)
        .background(DS.canvas)
        .scrollIndicators(.never, axes: [.horizontal, .vertical])
        .onChange(of: rows.map(\.id)) { _, names in
            if let focusedNode, !names.contains(focusedNode) { self.focusedNode = nil }
        }
    }

    private var nodeTable: some View {
        GeometryReader { geometry in
            nodeTable(width: geometry.size.width)
        }
    }

    private func nodeTable(width: CGFloat) -> some View {
        Table(rows, selection: $focusedNode) {
            TableColumn("Name") { row in
                HStack(spacing: 6) {
                    Button { onSelect(row.id) } label: {
                        Image(systemName: row.selected ? "checkmark.circle.fill" : row.active ? "circle.inset.filled" : "circle")
                            .foregroundStyle(row.selected || row.active ? (focusedNode == row.id ? Color.primary : DS.accent) : Color.secondary.opacity(0.5))
                            .frame(width: 24, height: 24).contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(!canSelect || busy)
                        .accessibilityLabel(row.selected ? "Selected: " + row.id : "Use " + row.id)
                        .help(group?.type == "LoadBalance" ? "This group balances connections automatically" : row.selected ? "Selected node" : row.active ? "Current automatic node · Click to pin" : "Use " + row.id)
                    Text(row.id).lineLimit(1).truncationMode(.middle).help(row.id)
                }
            }.width(max(110, width - 322))
            TableColumn("Country") { row in
                Text(ProxyCountryLabel.code(in: row.id) ?? "—").foregroundStyle(.secondary)
                    .help("Region from the subscription name; not a verified exit location")
            }.width(58)
            TableColumn("Type") { row in
                Text(Self.typeLabel(row.type)).foregroundStyle(.secondary).lineLimit(1).help(row.type)
            }.width(72)
            TableColumn("Latency") { row in
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Spacer(minLength: 0)
                    if row.testing {
                        ProgressView().controlSize(.mini).accessibilityLabel("Testing latency")
                    } else {
                        Text(row.delay.flatMap { $0 > 0 ? String($0) : nil } ?? "—")
                            .monospacedDigit().foregroundStyle(Color.latency(row.delay))
                        if let delay = row.delay, delay > 0 { Text("ms").font(DS.Typography.caption).foregroundStyle(.secondary) }
                    }
                }.help(row.testing ? "Testing" : row.delay.map { $0 > 0 ? "\($0) milliseconds" : "Unavailable" } ?? "Not measured")
            }.width(78)
            TableColumn("") { row in
                Button { onTest(row.id) } label: { ProxyLatencySymbol().frame(width: 24, height: 24) }
                    .buttonStyle(.borderless).disabled(!canTest || row.testing)
                    .help(canTest ? "Test latency for " + row.id : "Connect to test latency")
                    .accessibilityLabel("Test latency for " + row.id)
            }.width(28)
        }
        .contextMenu(forSelectionType: String.self) { selection in
            if let name = selection.first, selection.count == 1 {
                Button("Use Node") { onSelect(name) }.disabled(!canSelect || busy)
                Button("Test Latency") { onTest(name) }.disabled(!canTest || rows.first(where: { $0.id == name })?.testing == true)
            }
        } primaryAction: { selection in
            if let name = selection.first, selection.count == 1, canSelect, !busy { onSelect(name) }
        }
        .overlay {
            if rows.isEmpty {
                ContentUnavailableView(search.isEmpty ? "No members" : "No matching nodes", systemImage: search.isEmpty ? "network.slash" : "magnifyingglass")
                    .allowsHitTesting(false)
            }
        }
        .accessibilityLabel("Nodes in " + (selectedGroup ?? "group"))
    }

    static func typeLabel(_ type: String) -> String {
        switch type.lowercased() {
        case "selector", "select": "Select"
        case "urltest", "url-test": "URL Test"
        case "loadbalance", "load-balance": "Balance"
        case "fallback": "Fallback"
        case "direct": "Direct"
        case "reject", "rejectdrop", "reject-drop": "Reject"
        case "ss": "SS"
        case "socks5": "SOCKS5"
        case "—": "—"
        default: type.uppercased()
        }
    }
}
