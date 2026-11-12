import SwiftUI

struct ActivityViewPicker: View {
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 4) {
            viewButton("Topology", symbol: "point.3.connected.trianglepath.dotted", value: 0)
            viewButton("Connections", symbol: "list.bullet", value: 1)
        }
        .fixedSize()
    }

    private func viewButton(_ title: String, symbol: String, value: Int) -> some View {
        Button {
            selection = value
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(selection == value ? Color.accentColor : Color.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selection == value ? .isSelected : [])
    }
}
