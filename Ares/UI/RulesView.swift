import SwiftUI

struct RulesView: View {
    @EnvironmentObject var clashController: ClashController
    @State private var searchText = ""
    @AppStorage("localRules") private var localRules = ""
    @State private var showingLocalRulesEditor = false
    @State private var sortOrder = [KeyPathComparator(\ClashRule.hit, order: .reverse)]

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
        return result.sorted(using: sortOrder)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            Divider()

            // Table is the right control for uniform, sortable rule rows.
            Table(filteredRules, sortOrder: $sortOrder) {
                TableColumn("Type", value: \.type) { rule in
                    DSTag(text: rule.type, tint: RuleKindTint.tint(for: rule.type))
                }
                .width(min: 96, ideal: 120, max: 170)

                TableColumn("Payload", value: \.payload) { rule in
                    Text(rule.payload)
                        .font(DS.Typography.metadata.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.primary)
                }

                TableColumn("Proxy", value: \.proxy) { rule in
                    proxyCell(rule.proxy)
                }
                .width(min: 100, ideal: 160, max: 220)

                TableColumn("Hits", value: \.hit) { rule in
                    Text("\(rule.hit)")
                        .font(DS.Typography.metadata.monospaced())
                        .monospacedDigit()
                        .foregroundStyle(rule.hit > 0 ? HierarchicalShapeStyle.secondary : HierarchicalShapeStyle.tertiary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, DS.Space.xs)
                }
                .width(60)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Rules")
        .task {
            await Task.yield()
            try? await clashController.fetchRules()
        }
        .sheet(isPresented: $showingLocalRulesEditor) {
            LocalRulesEditorView(rules: $localRules) {
                Task {
                    // Rebuild config and reload Clash
                    await ProfileService.shared.reloadClashWithCurrentProfile()
                }
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: DS.Space.md) {
            TextField("Search \(filteredRules.count) rules", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .frame(width: 220)

            Spacer(minLength: DS.Space.sm)

            Text("\(filteredRules.count) rules")
                .font(DS.Typography.metadata)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Button {
                showingLocalRulesEditor = true
            } label: {
                Label("Local Rules", systemImage: "plus.message")
                    .font(DS.Typography.metadata.weight(.medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Add local rule overrides")
        }
        .padding(.horizontal, DS.Space.lg)
        .padding(.top, DS.Space.pageTop)
        .padding(.bottom, DS.Space.md)
    }

    // MARK: - Cells

    @ViewBuilder
    private func proxyCell(_ proxy: String) -> some View {
        switch proxy.lowercased() {
        case "direct":
            DSStatusPill(text: proxy, status: .good)
        case "reject":
            DSStatusPill(text: proxy, status: .critical)
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

// MARK: - Local rules editor

struct LocalRulesEditorView: View {
    @Binding var rules: String
    var onSave: () -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: DS.Space.lg) {
            DSCardHeader("Local Rule Overrides", icon: "text.badge.plus") {
                HStack(spacing: DS.Space.sm) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .controlSize(.small)

                    Button("Save & Apply") {
                        onSave()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }

            VStack(alignment: .leading, spacing: DS.Space.sm) {
                TextEditor(text: $rules)
                    .font(DS.Typography.secondary.monospaced())
                    .scrollContentBackground(.hidden)
                    .padding(DS.Space.sm)
                    .frame(minWidth: 500, minHeight: 400)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                            .strokeBorder(Color(nsColor: .separatorColor).opacity(0.9), lineWidth: DS.hairline)
                    )

                Text("One rule per line, injected above the subscription rules: - TYPE,PAYLOAD,PROXY")
                    .font(DS.Typography.metadata)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(DS.Space.lg)
        .frame(minWidth: 540)
        .background(DS.canvas)
    }
}
