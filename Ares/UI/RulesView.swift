import SwiftUI

struct RulesView: View {
    @EnvironmentObject var clashController: ClashController
    @State private var searchText = ""
    
    var filteredRules: [ClashRule] {
        if searchText.isEmpty {
            return clashController.rules
        } else {
            return clashController.rules.filter { 
                $0.type.localizedCaseInsensitiveContains(searchText) || 
                $0.payload.localizedCaseInsensitiveContains(searchText) || 
                $0.proxy.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar with Search
            HStack {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search rules...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
                .frame(maxWidth: 300)
                
                Spacer()
                
                Text("\(filteredRules.count) Rules")
                    .font(.footnote)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            
            // Rules List
            // Using Table for better macOS look and performance
            Table(filteredRules) {
                TableColumn("Type") { rule in
                    Text(rule.type)
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(typeColor(rule.type).opacity(0.1))
                        .foregroundStyle(typeColor(rule.type))
                        .cornerRadius(4)
                }
                .width(min: 80, max: 120)
                
                TableColumn("Payload") { rule in
                    Text(rule.payload)
                        .font(.body)
                        .lineLimit(1)
                }
                
                TableColumn("Proxy") { rule in
                    HStack {
                        Image(systemName: proxyIcon(rule.proxy))
                        Text(rule.proxy)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(proxyColor(rule.proxy))
                }
                .width(min: 100, max: 200)
            }
        }
        .navigationTitle("Rules")
        .task {
            await Task.yield()
            try? await clashController.fetchRules()
        }
    }
    
    private func typeColor(_ type: String) -> Color {
        switch type.lowercased() {
        case "domain", "domain-suffix", "domain-keyword": return .blue
        case "ip-cidr", "ip-cidr6": return .orange
        case "geoip": return .purple
        case "user-agent": return .green
        default: return .secondary
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
