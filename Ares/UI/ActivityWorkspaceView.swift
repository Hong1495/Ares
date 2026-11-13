import SwiftUI

/// One Activity destination with a topology overview and detailed connections.
struct ActivityWorkspaceView: View {
    @State private var selection = 0
    @State private var showDiagnostics = false

    var body: some View {
        Group {
            if selection == 0 {
                TopologyPageView()
            } else {
                ConnectionsView()
            }
        }
        .navigationTitle("")
        .sheet(isPresented: $showDiagnostics) { ActivityDiagnosticsView() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: DS.Space.md) {
                    Button { showDiagnostics = true } label: { Image(systemName: "checkmark.magnifyingglass").font(.system(size: 13)) }
                        .buttonStyle(.borderless).help("Runtime Diagnostics").accessibilityLabel("Runtime Diagnostics")
                    ActivityViewPicker(selection: $selection)
                }
            }.aresUnframed()
        }
    }
}
