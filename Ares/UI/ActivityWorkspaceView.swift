import SwiftUI

/// One Activity destination with a topology overview and detailed connections.
struct ActivityWorkspaceView: View {
    @State private var selection = 0
    @State private var showDiagnostics = false
    @State private var showApplicationRouting = false
    @State private var showQuality = false

    var body: some View {
        Group {
            if selection == 0 {
                TopologyPageView()
            } else {
                ConnectionsView()
            }
        }
        .navigationTitle("")
        .sheet(isPresented: $showApplicationRouting) { ApplicationRoutingView() }
        .sheet(isPresented: $showQuality) { NetworkQualityView() }
        .sheet(isPresented: $showDiagnostics) { ActivityDiagnosticsView() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: DS.Space.md) {
                    Button { showApplicationRouting = true } label: { Image(systemName: "app.connected.to.app.below.fill").font(.system(size: 13)) }
                        .buttonStyle(.borderless).help("Application Routing").accessibilityLabel("Application Routing")
                    Button { showQuality = true } label: { Image(systemName: "waveform.path.ecg").font(.system(size: 13)) }
                        .buttonStyle(.borderless).help("Network Quality").accessibilityLabel("Network Quality")
                    Button { showDiagnostics = true } label: { Image(systemName: "checkmark.magnifyingglass").font(.system(size: 13)) }
                        .buttonStyle(.borderless).help("Runtime Diagnostics").accessibilityLabel("Runtime Diagnostics")
                    ActivityViewPicker(selection: $selection)
                }
            }.aresUnframed()
        }
    }
}
