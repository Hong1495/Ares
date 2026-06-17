import SwiftUI

struct NodeAnalysisCard: View {
    @EnvironmentObject var clashController: ClashController
    @State private var avgDelay: Int = 0
    @State private var nodeCount: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            // 1. Header Zone
            HStack(spacing: 12) {
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.system(size: 18, weight: .light))
                    .frame(width: 24, height: 24, alignment: .center)
                    .foregroundStyle(.primary)

                Text("Node Analysis")
                    .font(.headline.weight(.medium))

                Spacer()
            }
            .frame(height: 24)
            .padding(16)

            Divider()
                .padding(.horizontal, 16)

            // 2. Content Zone
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Total Nodes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(nodeCount)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }

                HStack {
                    Text("Avg Latency")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(avgDelay) ms")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .foregroundStyle(delayColor(avgDelay))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 150)
        .cardStyle()
        .onReceive(clashController.$proxyNodes) { nodes in
            // Calculate stats
            self.nodeCount = nodes.count

            // Calc average of known delays
            let delays = nodes.values.compactMap { $0.delay }.filter { $0 > 0 }
            if !delays.isEmpty {
                self.avgDelay = delays.reduce(0, +) / delays.count
            }
        }
    }

    func delayColor(_ ms: Int) -> Color {
        if ms == 0 { return .secondary }
        if ms < 300 { return .green }
        if ms < 800 { return .orange }
        return .red
    }
}

/// Connections Card - Active Connections Stats
