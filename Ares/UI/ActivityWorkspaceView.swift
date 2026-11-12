import SwiftUI

/// One Activity destination with a topology overview and detailed connections.
struct ActivityWorkspaceView: View {
    @State private var selection = 0

    var body: some View {
        Group {
            if selection == 0 {
                TopologyPageView()
            } else {
                ConnectionsView()
            }
        }
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ActivityViewPicker(selection: $selection)
            }.aresUnframed()
        }
    }
}
