import SwiftUI

struct TopologyPageView: View {
    @EnvironmentObject var clashController: ClashController
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.6)

            TopologyView()
                .padding(DS.Space.lg)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DS.canvas)
        }
        .background(DS.canvas)
        .navigationTitle("Topology")
        .onAppear {
            Task { await clashController.monitorConnections() }
        }
    }

    private var header: some View {
        HStack(spacing: DS.Space.lg) {
            HStack(spacing: 5) {
                Text("Processes")
                    .font(DS.Typography.metadata)
                    .foregroundStyle(.secondary)
                Text("\(clashController.activeChains.count)")
                    .font(DS.Typography.metadata.monospaced().weight(.semibold))
            }

            Divider().frame(height: 12)

            HStack(spacing: 5) {
                Circle().fill(Color.seriesDown).frame(width: 6, height: 6)
                Text("Download")
                    .font(DS.Typography.metadata)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 5) {
                Circle().fill(Color.seriesUp).frame(width: 6, height: 6)
                Text("Upload")
                    .font(DS.Typography.metadata)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button {
                appState.animationsEnabled.toggle()
            } label: {
                Label(
                    appState.animationsEnabled ? "Pause" : "Animate",
                    systemImage: appState.animationsEnabled ? "pause.fill" : "play.fill"
                )
                .font(DS.Typography.metadata.weight(.medium))
            }
            .buttonStyle(.borderless)
            .help("Toggle traffic animation")
        }
        .padding(.horizontal, DS.Space.xl)
        .padding(.vertical, DS.Space.md)
    }
}

/// Kept for compatibility with call sites that render a compact stat chip.
struct StatBadge: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            Image(systemName: icon)
                .font(DS.Typography.secondary.weight(.medium))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(DS.Typography.body.weight(.semibold))
                    .monospacedDigit()
                Text(label)
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, DS.Space.md)
        .padding(.vertical, DS.Space.sm)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }
}
