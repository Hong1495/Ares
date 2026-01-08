import SwiftUI

struct PoliciesView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab Switcher
            Picker("Policy Tab", selection: $selectedTab) {
                Text("Proxies").tag(0)
                Text("Rules").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // Content
            if selectedTab == 0 {
                ProxiesView()
            } else {
                RulesView()
            }
        }
        .navigationTitle("Policies")
    }
}
