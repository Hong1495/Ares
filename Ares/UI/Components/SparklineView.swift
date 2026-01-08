import SwiftUI
import Charts

struct SparklineView: View {
    let data: [Int64]
    let color: Color
    
    // Convert generic Int array to identifiable data points for Charts
    private struct DataPoint: Identifiable {
        let id = UUID()
        let index: Int
        let value: Int64
    }
    
    private var chartData: [DataPoint] {
        data.enumerated().map { index, value in
            DataPoint(index: index, value: value)
        }
    }
    
    var body: some View {
        Chart(chartData) { point in
            // Area with Gradient
            AreaMark(
                x: .value("Index", point.index),
                y: .value("Value", point.value)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(
                LinearGradient(
                    colors: [color.opacity(0.2), color.opacity(0.0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            
            // Line
            LineMark(
                x: .value("Index", point.index),
                y: .value("Value", point.value)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(color)
            .lineStyle(StrokeStyle(lineWidth: 1.5))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: .automatic(includesZero: true))
    }
}
