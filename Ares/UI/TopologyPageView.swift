import SwiftUI

struct TopologyPageView: View {
    @EnvironmentObject var clashController: ClashController

    private var snapshot: TopologySnapshot {
        TopologySnapshot(rows: clashController.activeChains.map {
            TopologyRow(source: $0.sourceProcess, rule: $0.rule, chain: $0.chains,
                        host: $0.host, destinationIP: $0.destinationIP)
        })
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical) {
                TopologyView(rows: snapshot.rows)
                    .frame(height: max(geometry.size.height - DS.Space.pageTop - DS.Space.lg,
                                       CGFloat(snapshot.maximumColumnCount + 1) * 36))
            }
        }
            .padding(.horizontal, DS.Space.lg)
            .padding(.bottom, DS.Space.lg)
            .padding(.top, DS.Space.pageTop)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DS.canvas)
            .toolbar {
                ActivityTitleToolbar(count: snapshot.processCount, topologySummary: snapshot.summary, subtitle: snapshot.subtitle)
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
