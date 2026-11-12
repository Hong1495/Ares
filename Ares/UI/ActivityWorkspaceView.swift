import SwiftUI

/// One Activity destination with a topology overview and detailed connections.
struct ActivityWorkspaceView: View {
    @State private var selection = 0

    var body: some View {
        VStack(spacing: 0) {
            DSPageTabs(titles: ["Topology", "Connections"], selection: $selection)
                .padding(.horizontal, DS.Space.lg)
                .padding(.vertical, DS.Space.sm)
            Divider()
            if selection == 0 {
                TopologyPageView()
            } else {
                ConnectionsView()
            }
        }
        .navigationTitle("Activity")
    }
}
