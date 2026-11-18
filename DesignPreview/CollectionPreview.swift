import SwiftUI

struct CollectionPreview: View {
    let subscriptions: Bool
    let empty: Bool
    @State private var search = ""
    @State private var selected = "Personal"
    @State private var notice: String?
    @State private var sortOrder = [KeyPathComparator(\SampleRule.hits, order: .reverse)]
    private let rules = [
        SampleRule(type: "DOMAIN-SUFFIX", payload: "apple.com", proxy: "DIRECT", hits: 124),
        SampleRule(type: "DOMAIN-SUFFIX", payload: "github.com", proxy: "Automatic", hits: 87),
        SampleRule(type: "GEOIP", payload: "LAN", proxy: "DIRECT", hits: 19),
        SampleRule(type: "MATCH", payload: "", proxy: "Automatic", hits: 3)
    ]
    private var filteredRules: [SampleRule] {
        (empty ? [] : rules).filter { search.isEmpty || "\($0.type) \($0.payload) \($0.proxy)".localizedCaseInsensitiveContains(search) }.sorted(using: sortOrder)
    }
    var body: some View {
        VStack(spacing: 0) {
            CollectionTools(placeholder: subscriptions ? "Search subscriptions" : "Search rules", search: $search) {
                if subscriptions {
                    WorkspaceAction(title: "Add Subscription…", symbol: "plus", primary: true) { notice = "Add remote subscription" }
                    WorkspaceAction(title: "Import File…", symbol: "square.and.arrow.down") { notice = "Import local file" }
                } else {
                    WorkspaceAction(title: "Edit Local Rules…", symbol: "pencil", primary: true) { notice = "Edit local rules" }
                    WorkspaceAction(title: "Sources", symbol: "doc.text.magnifyingglass") { notice = "Rule sources" }
                    WorkspaceAction(title: "Rule Sets", symbol: "square.stack") { notice = "Rule sets" }
                }
            }
            Divider()
            if subscriptions {
                ScrollView {
                    let names = (empty ? [] : ["Personal", "Local configuration"]).filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) }
                    if names.isEmpty {
                        ContentUnavailableView("No subscriptions", systemImage: "rectangle.stack").frame(maxWidth: .infinity).padding(.top, 60)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 290), spacing: 12)], spacing: 12) {
                            ForEach(names, id: \.self) { name in
                                VStack(alignment: .leading, spacing: 12) {
                                    SubscriptionHeading(name: name, source: name == "Personal" ? "example.com" : "Local configuration", remote: name == "Personal", selected: selected == name)
                                    if name == "Personal" {
                                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                                            Text("28.4 GB").font(.system(size: 12, weight: .semibold))
                                            Text("of 200 GB").font(.system(size: 11)).foregroundStyle(.secondary)
                                        }
                                        ProgressView(value: 0.142).tint(DS.accent)
                                        Text("Expires Dec 31, 2026 · Updated today").font(.system(size: 10)).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                    HStack(spacing: 4) {
                                        Button(selected == name ? "Selected" : "Use profile") { selected = name }
                                            .buttonStyle(.bordered).controlSize(.small)
                                        Spacer()
                                        if name == "Personal" {
                                            WorkspaceAction(title: "Update", symbol: "arrow.clockwise") { notice = "Update subscription" }
                                        }
                                        Menu {
                                            Button("Rename…") { notice = "Rename subscription" }
                                            Button("Edit Configuration…") { notice = "Edit configuration" }
                                            Divider()
                                            Button("Delete…", role: .destructive) { notice = "Delete subscription" }
                                        } label: { Image(systemName: "ellipsis.circle") }
                                            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                                    }.font(.system(size: 13, weight: .regular)).buttonStyle(.borderless)
                                }.modifier(SubscriptionSurface(selected: selected == name))
                            }
                        }.padding(16)
                    }
                }
            } else {
                Table(filteredRules, sortOrder: $sortOrder) {
                    TableColumn("Type", value: \.type) { Text($0.type).font(.system(size: 11)).foregroundStyle(.secondary) }.width(min: 96, ideal: 120, max: 170)
                    TableColumn("Payload", value: \.payload) { Text($0.payload).font(.system(size: 11, design: .monospaced)) }
                    TableColumn("Proxy", value: \.proxy).width(min: 100, ideal: 160, max: 220)
                    TableColumn("Hits", value: \.hits) { Text(String($0.hits)).font(.system(size: 11, design: .monospaced)).frame(maxWidth: .infinity, alignment: .trailing) }.width(60)
                }.scrollIndicators(.hidden)
            }
        }.background(DS.canvas)
            .alert("Preview only", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
                Button("Done") { notice = nil }
            } message: { Text(notice ?? "") }
    }
}

private struct SampleRule: Identifiable {
    var id: String { type + payload }
    let type: String
    let payload: String
    let proxy: String
    let hits: Int
}
