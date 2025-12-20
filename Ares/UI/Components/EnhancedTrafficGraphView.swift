import SwiftUI
import Charts
import Combine

/// Enhanced Real-time Traffic Graph using SwiftUI Charts
struct EnhancedTrafficGraphView: View {
    @StateObject private var viewModel = TrafficGraphViewModel()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
            
            // Speed Chart using SwiftUI Charts
            Chart(viewModel.dataPoints) { point in
                // Upload Area
                AreaMark(
                    x: .value("Time", point.time),
                    y: .value("Upload", Double(point.upload))
                )
                .foregroundStyle(LinearGradient(
                    colors: [.cyan.opacity(0.2), .cyan.opacity(0.0)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .interpolationMethod(.catmullRom)
                
                // Upload Line
                LineMark(
                    x: .value("Time", point.time),
                    y: .value("Upload", Double(point.upload))
                )
                .foregroundStyle(.cyan)
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2))
                
                // Download Area
                AreaMark(
                    x: .value("Time", point.time),
                    y: .value("Download", Double(point.download))
                )
                .foregroundStyle(LinearGradient(
                    colors: [.green.opacity(0.2), .green.opacity(0.0)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .interpolationMethod(.catmullRom)
                
                // Download Line
                LineMark(
                    x: .value("Time", point.time),
                    y: .value("Download", Double(point.download))
                )
                .foregroundStyle(.green)
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2))
            }
            .chartYScale(domain: .automatic(includesZero: true))
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .chartXAxis(.hidden)
            .frame(height: 180)
            .padding(.vertical, 12)
            .padding(.horizontal)
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .task {
            await Task.yield()
            viewModel.startMonitoring()
        }
        .onDisappear {
            viewModel.stopMonitoring()
        }
    }
    
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
    
    init() {
        // Initialize with 60 data points
        let now = Date()
        dataPoints = (0..<60).map { i in
            TrafficDataPoint(
                time: now.addingTimeInterval(Double(i - 60)),
                upload: 0,
                download: 0
            )
        }
    }
    
    func startMonitoring() {
        // Immediately update with current data if available
        let current = ClashController.shared.traffic
        updateTraffic(up: current.up, down: current.down)
        
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
        DispatchQueue.main.async {
            self.currentUpload = up
            self.currentDownload = down
            
            // Update graph data
            let newPoint = TrafficDataPoint(
                time: Date(),
                upload: up,
                download: down
            )
            
            self.dataPoints.append(newPoint)
            if self.dataPoints.count > 60 {
                self.dataPoints.removeFirst()
            }
        }
    }
}
