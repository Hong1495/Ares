import SwiftUI

struct ConnectionsCard: View {
    @EnvironmentObject var clashController: ClashController
    @EnvironmentObject var clashViewModel: ClashViewModel
    @State private var totalConnections: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            // 1. Header Zone
            HStack(spacing: 12) {
                Image(systemName: "network")
                    .font(.system(size: 18, weight: .light))
                    .frame(width: 24, height: 24, alignment: .center)
                    .foregroundStyle(.primary)

                Text("Connections")
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
                    Text("Active")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(totalConnections)")
                        .font(.title2) // Prominent number
                        .fontWeight(.bold)
                        .monospacedDigit()
                }

                // Optional: Show current bandwidth as summary
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                        Text("\(formatBytes(clashController.traffic.down))/s")
                            .font(.caption2)
                            .monospacedDigit()
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                        Text("\(formatBytes(clashController.traffic.up))/s")
                            .font(.caption2)
                            .monospacedDigit()
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 150)
        .cardStyle()
        .task {
            // Wait for Clash to be fully ready
            while !clashViewModel.isRunning || clashViewModel.isToggling {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)

            // Poll connections count every few seconds
            while !Task.isCancelled {
                if clashViewModel.isRunning && !clashViewModel.isToggling {
                    do {
                        let json = try await clashController.fetchConnections()
                        if let connections = json["connections"] as? [[String: Any]] {
                            await MainActor.run {
                                self.totalConnections = connections.count
                            }
                        }
                    } catch {}
                }
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5s
            }
        }
    }

    func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bytes)
    }
}

/// Error Log Card - Showing recent errors
