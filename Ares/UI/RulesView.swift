import SwiftUI

struct RulesView: View {
    @EnvironmentObject var clashController: ClashController
    @State private var searchText = ""
    private struct RuleDraft: Identifiable {
        let id = UUID()
        let text: String
        let revision: String
    }
    @State private var editor: RuleDraft?
    @State private var showingProviders = false
    @State private var showingSources = false

    var filteredRules: [ClashRule] {
        let result: [ClashRule]
        if searchText.isEmpty {
            result = clashController.rules
        } else {
            result = clashController.rules.filter {
                $0.type.localizedCaseInsensitiveContains(searchText) ||
                $0.payload.localizedCaseInsensitiveContains(searchText) ||
                $0.proxy.localizedCaseInsensitiveContains(searchText)
            }
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            Divider()

            if let error = clashController.rulesError {
                Text(error).font(DS.Typography.metadata).foregroundStyle(.secondary)
                    .padding(DS.Space.md)
            }
            // Order is the core's matching priority, including when filtering.
            Table(filteredRules) {
                TableColumn("Order") { rule in
                    Text("\(rule.index + 1)").font(DS.Typography.metadata.monospacedDigit())
                        .foregroundStyle(.secondary)
                }.width(50)
                TableColumn("Type") { rule in
                    Text(rule.type).font(DS.Typography.metadata)
                        .strikethrough(rule.extra?.disabled == true)
                        .help(rule.extra?.disabled == true ? "Disabled in the running core" : rule.type)
                        .foregroundStyle(RuleKindTint.tint(for: rule.type)).lineLimit(1)
                }
                .width(min: 96, ideal: 120, max: 170)

                TableColumn("Payload") { rule in
                    Text(rule.payload)
                        .font(DS.Typography.metadata.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.primary)
                }

                TableColumn("Proxy") { rule in
                    proxyCell(rule.proxy)
                }
                .width(min: 100, ideal: 160, max: 220)

                TableColumn("Hits") { rule in
                    Text(rule.hit.map(String.init) ?? "—")
                        .font(DS.Typography.metadata.monospaced())
                        .monospacedDigit()
                        .foregroundStyle((rule.hit ?? 0) > 0 ? HierarchicalShapeStyle.secondary : HierarchicalShapeStyle.tertiary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, DS.Space.xs)
                }
                .width(60)
            }
            .scrollIndicators(.never)
        }
        .background(DS.canvas)
        .navigationTitle("")
        .toolbar { CollectionTitleToolbar(title: "Rules", count: clashController.rules.count, unit: "Rules") }
        .task {
            await Task.yield()
            try? await clashController.fetchRules()
        }
        .sheet(item: $editor) { draft in
            LocalRulesEditorView(initialRules: draft.text, revision: draft.revision)
        }
        .sheet(isPresented: $showingSources) { RuleSourcesView() }
        .sheet(isPresented: $showingProviders) {
            RuleProvidersView().environmentObject(clashController)
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        CollectionTools(placeholder: "Search rules", search: $searchText) {
            Button { showingSources = true } label: {
                Image(systemName: "doc.text.magnifyingglass").frame(width: 16, height: 16)
            }.help("Inspect rule sources").accessibilityLabel("Inspect rule sources")
            Button { showingProviders = true } label: {
                Image(systemName: "square.stack").frame(width: 16, height: 16)
            }.help("Rule sets").accessibilityLabel("Rule sets")
            Button {
                editor = RuleDraft(text: UserDefaults.standard.string(forKey: DefaultsKeys.localRules) ?? "",
                    revision: ProfileService.shared.activeProfileRevision)
            } label: {
                Image(systemName: "text.badge.plus").frame(width: 16, height: 16)
            }
            .help("Edit local rule overrides")
            .accessibilityLabel("Edit local rules")
        }
    }

    // MARK: - Cells

    @ViewBuilder
    private func proxyCell(_ proxy: String) -> some View {
        switch proxy.lowercased() {
        case "direct":
            Text(proxy).font(DS.Typography.metadata).foregroundStyle(.secondary)
        case "reject":
            Text(proxy).font(DS.Typography.metadata).foregroundStyle(Color.statusBad)
        default:
            Text(proxy)
                .font(DS.Typography.metadata)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

// MARK: - Rule kind tint

/// Rule kinds are mapped onto documented design-system roles only.
/// The system ships a validated series pair (blue/orange) plus the status
/// ramp, so kinds borrow from those instead of introducing ad-hoc hues:
/// domain family = seriesDown, IP family = seriesUp, GEOIP = warning,
/// process/agent = idle, FINAL = secondary.
private enum RuleKindTint {
    static func tint(for type: String) -> Color {
        let normalized = type.uppercased()
        switch normalized {
        case "DOMAIN", "DOMAIN-SUFFIX", "DOMAIN-KEYWORD", "DOMAIN-REGEX":
            return .seriesDown
        case "IP-CIDR", "IP-CIDR6", "SRC-IP-CIDR", "SRC-IP-CIDR6", "IP-SUFFIX":
            return .seriesUp
        case "GEOIP", "GEOSITE":
            return .statusWarn
        case "USER-AGENT", "PROCESS-NAME", "PROCESS-PATH":
            return .statusIdle
        case "FINAL", "MATCH":
            return .secondary
        default:
            return .secondary
        }
    }
}
