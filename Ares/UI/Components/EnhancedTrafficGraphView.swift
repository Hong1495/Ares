import SwiftUI
import Charts
import Combine

/// Enhanced Real-time Traffic Graph using SwiftUI Charts
struct EnhancedTrafficGraphView: View {
    @StateObject private var viewModel = TrafficGraphViewModel()
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
                            Text(formatSpeed(viewModel.currentUpload))
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
                            Text(formatSpeed(viewModel.currentDownload))
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
            let uploadData = viewModel.dataPoints.map { ($0.time, Double($0.upload)) }
            let downloadData = viewModel.dataPoints.map { ($0.time, Double($0.download)) }

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
        .task {
            await Task.yield()
            viewModel.startMonitoring()
        }
        .onDisappear {
            viewModel.stopMonitoring()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    viewModel.startMonitoring()
                }
            } else if newPhase == .background {
                viewModel.stopMonitoring()
            }
        }
    }

    @Environment(\.scenePhase) private var scenePhase

    private func formatSpeed(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        let formatted = formatter.string(fromByteCount: bytes)
        return formatted == "Zero KB" ? "0 KB/s" : formatted + "/s"
    }
}

/// Data point for chart
struct TrafficDataPoint: Identifiable {
    let id = UUID()
    let time: Date
    let upload: Int64
    let download: Int64
}

/// ViewModel for traffic monitoring
@MainActor
class TrafficGraphViewModel: ObservableObject {
    @Published var dataPoints: [TrafficDataPoint] = []
    @Published var currentUpload: Int64 = 0
    @Published var currentDownload: Int64 = 0

    private var cancellables = Set<AnyCancellable>()

    func startMonitoring() {
        guard cancellables.isEmpty else { return }

        // Observe ClashController traffic updates
        ClashController.shared.$traffic
            .receive(on: RunLoop.main)
            .sink { [weak self] traffic in
                self?.updateTraffic(up: traffic.up, down: traffic.down)
            }
            .store(in: &cancellables)
    }

    func stopMonitoring() {
        cancellables.removeAll()
    }

    private func updateTraffic(up: Int64, down: Int64) {
        // 已在 @MainActor 上，无需再次调度到主线程
        self.currentUpload = up
        self.currentDownload = down

        // Update graph data
        let newPoint = TrafficDataPoint(
            time: Date(),
            upload: up,
            download: down
        )

        self.dataPoints.append(newPoint)
        // Keep the full time window and one preceding sample for the left edge.
        let cutoff = newPoint.time.addingTimeInterval(-60)
        while dataPoints.count > 2 && dataPoints[1].time < cutoff {
            dataPoints.removeFirst()
        }
    }
}
