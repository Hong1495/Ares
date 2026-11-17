import SwiftUI

/// Enhanced Real-time Traffic Graph using SwiftUI Charts
struct EnhancedTrafficGraphView: View {
    @ObservedObject private var history = ClashController.shared.trafficHistory
    @EnvironmentObject private var appState: AppState
    var showHeader: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: showHeader ? 12 : 0) {
            if showHeader {
                HStack {
                    Label("Network Traffic", systemImage: "chart.xyaxis.line")
                        .font(.headline)
                    Spacer()

                    // Legend with traffic rates
                    HStack(spacing: 16) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(.cyan)
                                .frame(width: 8, height: 8)
                            Text("Upload")
                                .font(.footnote)
                                .fontWeight(.medium)
                            Text(formatSpeed(history.snapshot.currentUpload))
                                .font(.footnote)
                                .fontWeight(.semibold)
                                .monospacedDigit()
                                .foregroundStyle(.cyan)
                        }
                        HStack(spacing: 6) {
                            Circle()
                                .fill(.green)
                                .frame(width: 8, height: 8)
                            Text("Download")
                                .font(.footnote)
                                .fontWeight(.medium)
                            Text(formatSpeed(history.snapshot.currentDownload))
                                .font(.footnote)
                                .fontWeight(.semibold)
                                .monospacedDigit()
                                .foregroundStyle(.green)
                        }
                    }
                    .foregroundStyle(.secondary)
                }
            }

            // Speed Chart using SmoothGraphView for 60fps scrolling
            let uploadData = history.snapshot.points.map { ($0.time, Double($0.upload)) }
            let downloadData = history.snapshot.points.map { ($0.time, Double($0.download)) }

            DualSmoothGraphView(
                uploadData: uploadData,
                downloadData: downloadData,
                visibleDuration: 60,
                appState: appState
            )
            .frame(height: showHeader ? 180 : 80)
            .padding(.vertical, showHeader ? 12 : 4)
            .padding(.horizontal, showHeader ? 16 : 8)
        }
        .padding(showHeader ? 16 : 4)
        .background(showHeader ? Color(nsColor: .controlBackgroundColor) : Color.clear)
        .cornerRadius(showHeader ? 8 : 0)
    }

    private func formatSpeed(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        let formatted = formatter.string(fromByteCount: bytes)
        return formatted == "Zero KB" ? "0 KB/s" : formatted + "/s"
    }
}
