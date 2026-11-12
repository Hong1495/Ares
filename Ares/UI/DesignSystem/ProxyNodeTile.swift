import SwiftUI

/// Shared by live proxy groups and the service-free preview.
struct SimpleProxyButton: View {
    let name: String
    let isSelected: Bool
    let delay: Int?
    let isTesting: Bool
    var canSelect: Bool = true
    var canTest: Bool = true
    let onSelect: () -> Void
    let onTest: () -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isSelected ? DS.accent : Color.secondary.opacity(0.5))
                        Text(name).font(DS.Typography.secondary.weight(.medium)).lineLimit(1).truncationMode(.middle)
                    }
                    HStack(spacing: 6) {
                        Circle().fill(Color.latency(delay)).frame(width: 5, height: 5)
                        Text(delay.map { "\($0) ms" } ?? "Not measured")
                            .font(DS.Typography.metadata.monospaced()).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canSelect)
            .help(canSelect ? "Select \(name)" : "This group selects nodes automatically")
            .accessibilityLabel("Select \(name)")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            if isTesting {
                ProgressView().controlSize(.mini)
            } else {
                Button(action: onTest) {
                    Image(systemName: "bolt.horizontal").font(DS.Typography.metadata).frame(width: 22, height: 22)
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .disabled(!canTest)
                .help(canTest ? "Test latency for \(name)" : "Connect to test latency")
                .accessibilityLabel("Test latency for \(name)")
            }
        }
        .padding(14)
        .background(isSelected ? DS.accent.opacity(0.07) : (hovering ? DS.soft : .clear), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(isSelected ? DS.accent.opacity(0.45) : DS.line, lineWidth: DS.hairline))
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: hovering)
    }
}
