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
            DSPageTabs(titles: PolicyTab.allCases.map(\.title), selection: Binding(
                get: { selectedTab.rawValue },
                set: { selectedTab = PolicyTab(rawValue: $0) ?? .proxies }
            ))
            .padding(.horizontal, 30)
            .padding(.bottom, 18)

            switch selectedTab {
            case .proxies:
                ProxiesView()
            case .rules:
                RulesView()
            case .subscriptions:
                ProfilesView()
            }
        }
        .background(DS.canvas)
        .navigationTitle("Proxy & Rules")
    }
}
