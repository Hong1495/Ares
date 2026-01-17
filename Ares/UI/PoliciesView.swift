import SwiftUI

enum PolicyTab: Int, CaseIterable, Identifiable {
    case proxies = 0
    case rules = 1
    case subscriptions = 2
    
    var id: Int { rawValue }
    
    var title: String {
        switch self {
        case .proxies: return "Proxies"
        case .rules: return "Rules"
        case .subscriptions: return "Subscriptions"
        }
    }
    
    var icon: String {
        switch self {
        case .proxies: return "hand.tap"
        case .rules: return "list.bullet.indent"
        case .subscriptions: return "rectangle.stack"
        }
    }
}

struct PoliciesView: View {
    @State private var selectedTab: PolicyTab = .proxies
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab Switcher with icons
            HStack(spacing: 4) {
                ForEach(PolicyTab.allCases) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTab = tab
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 11, weight: .medium))
                            Text(tab.title)
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            selectedTab == tab ?
                            Color.blue :
                            Color.primary.opacity(0.05)
                        )
                        .foregroundStyle(selectedTab == tab ? .white : .primary)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // Content
            switch selectedTab {
            case .proxies:
                ProxiesView()
            case .rules:
                RulesView()
            case .subscriptions:
                ProfilesView()
            }
        }
        .navigationTitle("Policies")
    }
}
