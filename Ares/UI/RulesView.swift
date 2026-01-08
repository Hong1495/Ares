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
            // Toolbar with Search
            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 13, weight: .medium))
                        
                        TextField("Search among \(filteredRules.count) rules...", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                        
                        if !searchText.isEmpty {
                            Button {
                                withAnimation { searchText = "" }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary.opacity(0.8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    )
                    .frame(maxWidth: 400)
                    
                    Spacer()
                    
                    Button {
                        showingLocalRulesEditor = true
                    } label: {
                        Label("Local Rules", systemImage: "plus.message")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Add local rule overrides")
                }
                .padding()
                .background(Color(nsColor: .windowBackgroundColor))
                
                Divider()
            }
            
            // Rules List
            // Using Table for better macOS look and performance
            Table(filteredRules, sortOrder: $sortOrder) {
                TableColumn("Type", value: \.type) { rule in
                    Text(rule.type)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(typeColor(rule.type).opacity(0.12))
                        .foregroundStyle(typeColor(rule.type))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(typeColor(rule.type).opacity(0.2), lineWidth: 1)
                        )
                }
                .width(min: 80, max: 120)
                
                TableColumn("Payload", value: \.payload) { rule in
                    Text(rule.payload)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                        .foregroundStyle(.primary.opacity(0.9))
                }
                
                TableColumn("Proxy", value: \.proxy) { rule in
                    HStack(spacing: 8) {
                        Image(systemName: proxyIcon(rule.proxy))
                            .font(.system(size: 10))
                        Text(rule.proxy)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(proxyColor(rule.proxy).opacity(0.1))
                    .foregroundStyle(proxyColor(rule.proxy))
                    .cornerRadius(6)
                }
                .width(min: 100, max: 200)

                TableColumn("Hits", value: \.hit) { rule in
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 9))
                        Text("\(rule.hit)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(rule.hit > 0 ? Color.orange.opacity(0.15) : Color.primary.opacity(0.05))
                    .foregroundStyle(rule.hit > 0 ? Color.orange : Color.secondary)
                    .cornerRadius(6)
                    .frame(maxWidth: .infinity, alignment: .trailing)
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
    
    private func typeColor(_ type: String) -> Color {
        let normalized = type.uppercased()
        switch normalized {
        case "DOMAIN", "DOMAIN-SUFFIX", "DOMAIN-KEYWORD": return .blue
        case "IP-CIDR", "IP-CIDR6": return .purple
        case "GEOIP": return .orange
        case "USER-AGENT": return .green
        case "FINAL": return .secondary
        default: return .blue
        }
    }
    
    private func proxyColor(_ proxy: String) -> Color {
        switch proxy.lowercased() {
        case "direct": return .green
        case "reject": return .red
        default: return .blue
        }
    }
    
    private func proxyIcon(_ proxy: String) -> String {
        switch proxy.lowercased() {
        case "direct": return "arrow.turn.up.right"
        case "reject": return "shield.slash"
        default: return "arrow.right.circle"
        }
    }
}

struct LocalRulesEditorView: View {
    @Binding var rules: String
    var onSave: () -> Void
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Local Rule Overrides")
                        .font(.headline)
                    Text("Injected at the top of the rules list. Format: - TYPE,PAYLOAD,PROXY")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                
                HStack {
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.plain)
                    
                    Button("Save & Apply") {
                        onSave()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            TextEditor(text: $rules)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .textBackgroundColor))
                .padding(8)
                .frame(minWidth: 500, minHeight: 400)
        }
    }
}
