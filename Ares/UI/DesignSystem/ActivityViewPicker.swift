import SwiftUI

struct ActivityViewPicker: View {
    @Binding var selection: Int

    var body: some View {
        Picker("Activity view", selection: $selection) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .help("Topology")
                .accessibilityLabel("Topology")
                .tag(0)
            Image(systemName: "list.bullet")
                .help("Connections")
                .accessibilityLabel("Connections")
                .tag(1)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }
}
