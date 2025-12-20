import SwiftUI
import Charts

struct TrafficGraphView: View {
    @EnvironmentObject var clashController: ClashController
    // Mock historical data since ClashController currently only has instantaneous.
    // In a real implementation, we'd append to an array in ClashController.
    @State private var downloadHistory: [Int64] = Array(repeating: 0, count: 60)
    @State private var uploadHistory: [Int64] = Array(repeating: 0, count: 60)
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Traffic Trend")
                .font(.headline)
                .padding(.bottom, 8)
            
            Chart {
                ForEach(Array(downloadHistory.enumerated()), id: \.offset) { index, value in
                    LineMark(
                        x: .value("Time", index),
                        y: .value("Download", value),
                        series: .value("Type", "Download")
                    )
                    .foregroundStyle(.purple)
                    .interpolationMethod(.catmullRom)
                    
                    AreaMark(
                        x: .value("Time", index),
                        y: .value("Download", value)
                    )
                    .foregroundStyle(LinearGradient(colors: [.purple.opacity(0.3), .purple.opacity(0.0)], startPoint: .top, endPoint: .bottom))
                }
                
                ForEach(Array(uploadHistory.enumerated()), id: \.offset) { index, value in
                    LineMark(
                        x: .value("Time", index),
                        y: .value("Upload", value),
                        series: .value("Type", "Upload")
                    )
                    .foregroundStyle(.blue)
                    .interpolationMethod(.catmullRom)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 150)
            .onReceive(clashController.$traffic) { traffic in
                Task { @MainActor in
                    downloadHistory.append(traffic.down)
                    if downloadHistory.count > 60 { downloadHistory.removeFirst() }
                    
                    uploadHistory.append(traffic.up)
                    if uploadHistory.count > 60 { uploadHistory.removeFirst() }
                }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }
}
