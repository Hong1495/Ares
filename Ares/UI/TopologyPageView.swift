import SwiftUI

struct TopologyPageView: View {
    @EnvironmentObject var clashController: ClashController

    var body: some View {
        TopologyView()
            .padding(DS.Space.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DS.canvas)
            .toolbar {
                ActivityTitleToolbar(count: Set(clashController.activeChains.map(\.sourceProcess)).count)
            }
        .onAppear {
            Task { await clashController.monitorConnections() }
        }
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
