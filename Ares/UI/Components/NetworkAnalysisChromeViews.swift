import SwiftUI

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

struct StatusIndicator: View {
    @ObservedObject private var service = BrowserAnalysisService.shared
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: service.activeTabs.isEmpty ? "antenna.radiowaves.left.and.right.slash" : "antenna.radiowaves.left.and.right")
                .font(DS.Typography.caption.weight(.light))
                .foregroundStyle(service.activeTabs.isEmpty ? Color.secondary : Color.green)

            Circle()
                .fill(service.activeTabs.isEmpty ? Color.secondary : Color.green)
                .frame(width: 6, height: 6)

            Text(service.activeTabs.isEmpty ? "No active sessions" : "Monitoring Network Traffic")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(10)
        .background(Color.secondary.opacity(0.03))
    }
}

struct SearchField: View {
    @Binding var text: String
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .font(DS.Typography.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("Search...", text: $text)
                .textFieldStyle(.plain)
                .font(DS.Typography.metadata)
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 32, weight: .ultraLight))
                .foregroundStyle(.tertiary)
            Text("No Activity Captured")
                .font(DS.Typography.body.weight(.medium))
            Text("Network requests for this tab will appear here in real-time.")
                .font(DS.Typography.metadata)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 200)
        }
        .opacity(0.6)
    }
}
