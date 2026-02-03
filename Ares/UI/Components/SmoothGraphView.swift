import SwiftUI

// MARK: - Data Models

struct GraphDataPoint: Identifiable, Equatable {
    let id: UUID
    let date: Date
    let value: Double

    init(date: Date, value: Double) {
        self.id = UUID()
        self.date = date
        self.value = value
    }
}

// MARK: - Smooth Graph View (Single Line)
// Used for Sparklines and single-metric graphs
struct SmoothSparklineView: View {
    let data: [(Date, Double)]
    let color: Color
    let maxDataPoints: Int // Kept for API compatibility, but we use time-based logic now

    // Config
    private let visibleDuration: TimeInterval = 60 // Show last 60 seconds

    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if appState.animationsEnabled {
                TimelineView(.animation) { timeline in
                    chartCanvas(timeline: timeline)
                }
            } else {
                TimelineView(.explicit([Date()])) { timeline in
                    chartCanvas(timeline: timeline)
                }
            }
        }
        .drawingGroup()
    }

    @ViewBuilder
    private func chartCanvas(timeline: TimelineViewDefaultContext) -> some View {
        Canvas { context, size in
            let now = timeline.date.timeIntervalSinceReferenceDate
            let width = size.width
            let height = size.height

            let endT = now
            let startT = now - visibleDuration

            // Filter visible data
            let renderData = data.filter {
                let t = $0.0.timeIntervalSinceReferenceDate
                return t > startT - 5
            }

            guard renderData.count > 1 else { return }

            let maxVal = renderData.map { $0.1 }.max() ?? 1.0
            let range = (maxVal == 0) ? 1.0 : maxVal * 1.1 // Headroom

            func xPos(_ date: Date) -> CGFloat {
                let t = date.timeIntervalSinceReferenceDate
                let progress = (t - startT) / visibleDuration
                return CGFloat(progress) * width
            }

            func yPos(_ val: Double) -> CGFloat {
                return height - (CGFloat(val) / CGFloat(range) * height)
            }

            var path = Path()
            path.move(to: CGPoint(x: xPos(renderData[0].0), y: yPos(renderData[0].1)))

            for i in 1..<renderData.count {
                path.addLine(to: CGPoint(x: xPos(renderData[i].0), y: yPos(renderData[i].1)))
            }

            // Stroke
            context.stroke(path, with: .color(color), lineWidth: 1.5)

            // Fill
            var fillPath = path
            fillPath.addLine(to: CGPoint(x: xPos(renderData.last!.0), y: height))
            fillPath.addLine(to: CGPoint(x: xPos(renderData.first!.0), y: height))
            fillPath.closeSubpath()

            let gradient = Gradient(stops: [
                .init(color: color.opacity(0.3), location: 0),
                .init(color: color.opacity(0.0), location: 1)
            ])
            context.fill(fillPath, with: .linearGradient(gradient, startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: height)))
        }
    }
}

// MARK: - Dual Smooth Graph View (Dashboard)
// Uses TimelineView for true 60fps scrolling history

struct DualSmoothGraphView: View {
    let uploadData: [(Date, Double)]
    let downloadData: [(Date, Double)]
    var visibleDuration: TimeInterval = 60 // Seconds history to show

    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if appState.animationsEnabled {
                TimelineView(.animation) { timeline in
                    dualChartCanvas(timeline: timeline)
                }
            } else {
                TimelineView(.explicit([Date()])) { timeline in
                    dualChartCanvas(timeline: timeline)
                }
            }
        }
        .drawingGroup()
    }

    @ViewBuilder
    private func dualChartCanvas(timeline: TimelineViewDefaultContext) -> some View {
        Canvas { context, size in
            let now = timeline.date.timeIntervalSinceReferenceDate
            let width = size.width
            let height = size.height

            // Time Window
            let endT = now
            let startT = now - visibleDuration

            // Pre-calc Y scale (Max of both up/down in the visible range)
            let visibleUp = uploadData.filter { $0.0.timeIntervalSinceReferenceDate > startT }
            let visibleDown = downloadData.filter { $0.0.timeIntervalSinceReferenceDate > startT }

            let maxUp = visibleUp.map { $0.1 }.max() ?? 0
            let maxDown = visibleDown.map { $0.1 }.max() ?? 0
            let globalMax = max(maxUp, maxDown, 1024) * 1.2 // Add 20% headroom

            func xPos(_ date: Date) -> CGFloat {
                let t = date.timeIntervalSinceReferenceDate
                let progress = (t - startT) / visibleDuration
                return CGFloat(progress) * width
            }

            func yPos(_ val: Double) -> CGFloat {
                return height - (CGFloat(val) / CGFloat(globalMax) * height)
            }

            // Draw Function
            func drawLine(data: [(Date, Double)], color: Color) {
                var path = Path()
                guard let first = data.first else { return }

                // Optimisation: Only draw points near visible range
                // We include one point before startT to ensure line enters from left smoothly
                let renderData = data.filter {
                    let t = $0.0.timeIntervalSinceReferenceDate
                    return t > startT - 5 // Buffer
                }

                guard !renderData.isEmpty else { return }

                path.move(to: CGPoint(x: xPos(renderData[0].0), y: yPos(renderData[0].1)))

                for i in 1..<renderData.count {
                    let p = CGPoint(x: xPos(renderData[i].0), y: yPos(renderData[i].1))
                    path.addLine(to: p)
                }

                // Stroke
                context.stroke(path, with: .color(color), lineWidth: 2)

                // Fill (Gradient)
                var fillPath = path
                fillPath.addLine(to: CGPoint(x: xPos(renderData.last!.0), y: height))
                fillPath.addLine(to: CGPoint(x: xPos(renderData.first!.0), y: height))
                fillPath.closeSubpath()

                let gradient = Gradient(stops: [
                    .init(color: color.opacity(0.3), location: 0),
                    .init(color: color.opacity(0.0), location: 1)
                ])
                context.fill(fillPath, with: .linearGradient(gradient, startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: height)))
            }

            drawLine(data: uploadData, color: .cyan)
            drawLine(data: downloadData, color: .green)
        }
    }
}
