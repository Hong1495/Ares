import SwiftUI

struct TopologyPageView: View {
    @EnvironmentObject var clashController: ClashController

    var body: some View {
        VStack(spacing: 0) {


            // Full screen TopologyView content
            // We reuse the existing component but might want to expand it in the future
            // For now, wrapping it in a ScrollView to allow it to expand
            // Full screen TopologyView content
            TopologyView()
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
        }
        .navigationTitle("Topology")
        .onAppear {
            Task { await clashController.monitorConnections() }
        }
    }

    func formatBytes(_ bytes: Int64) -> String {
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

struct StatBadge: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.headline)
                    .monospaced()
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}
