import SwiftUI

struct SparklineView: View {
    let data: [(Date, Int64)] // Tuple format
    let color: Color

    var body: some View {
        SmoothSparklineView(
            data: data.map { ($0.0, Double($0.1)) }, // Map to (Date, Double)
            color: color,
            maxDataPoints: 60,
            animate: false
        )
        // Removed .animation, using TimelineView internal animation instead
    }
}
