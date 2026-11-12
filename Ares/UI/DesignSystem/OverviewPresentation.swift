import SwiftUI
import Charts

/// Value-only inputs keep network services outside the presentation layer.
struct OverviewSnapshot {
    var title: String
    var subtitle: String
    var status: DSStatus
    var runtime: String
    var node: String
    var latency: Int?
    var connections: Int?
    var download: String
    var upload: String
}

/// The production page and preview use the same layout, not parallel mockups.
struct DashboardComposition<Traffic: View, Controls: View, Details: View>: View {
    @ViewBuilder var traffic: () -> Traffic
    @ViewBuilder var controls: () -> Controls
    @ViewBuilder var details: () -> Details

    var body: some View {
        VStack(spacing: 20) {
            controls().fixedSize(horizontal: false, vertical: true)
            traffic().frame(maxWidth: .infinity, maxHeight: .infinity)
            details().fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 28).padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.canvas)
    }
}

struct OverviewConnectionCard: View {
    let snapshot: OverviewSnapshot
    @Binding var systemProxy: Bool
    @Binding var tun: Bool
    @Binding var interception: Bool
    @Binding var mode: Int
    var busy = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 22) {
                activation
                Rectangle().fill(DS.line).frame(width: 1, height: 24)
                modes
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 16) {
                HStack { activation; Spacer() }
                modes
            }
        }
        .padding(.vertical, 8)
        .disabled(busy)
    }

    private var activation: some View {
        HStack(spacing: 18) {
            capability("System proxy", icon: "power", value: $systemProxy)
            capability("TUN", icon: "point.topleft.down.to.point.bottomright.curvepath", value: $tun)
            capability("MITM", icon: "waveform.path", value: $interception)
        }.fixedSize()
    }

    private var modes: some View {
        Picker("Routing mode", selection: $mode) {
            ForEach(0..<3) { index in
                Text(["Rule", "Global", "Direct"][index]).tag(index)
            }
        }
        .pickerStyle(.segmented).labelsHidden().controlSize(.regular)
        .font(.system(size: 12)).frame(width: 204)
    }

    private func capability(_ title: String, icon: String, value: Binding<Bool>) -> some View {
        Toggle(isOn: value) {
            HStack(spacing: 7) {
                DashboardSymbol(name: icon).foregroundStyle(.secondary)
                Text(title).font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.primary)
        }.toggleStyle(.switch).controlSize(.small).tint(DS.accent)
            .accessibilityLabel(title).accessibilityValue(value.wrappedValue ? "On" : "Off")
            .help("\(value.wrappedValue ? "Disable" : "Enable") \(title)")
    }
}

/// Shared by the production probes and the isolated design preview.
struct OverviewReachability: View {
    struct Item: Identifiable {
        let id: String
        let name: String
        let icon: String
        let latency: Int?
        let loading: Bool
    }
    let items: [Item]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Rectangle().fill(DS.line).frame(height: 0.5)
            Text("Reachability").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            HStack(spacing: 24) {
                ForEach(items) { item in
                    ReachabilityResult(item: item)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

private struct ReachabilityResult: View {
    let item: OverviewReachability.Item
    private var status: String {
        if item.loading { return "Testing" }
        guard let ms = item.latency else { return "Not tested" }
        return ms < 0 ? "Unavailable" : "\(ms) milliseconds"
    }
    var body: some View {
        HStack(spacing: 8) {
                DashboardSymbol(name: item.icon).foregroundStyle(.secondary)
                Text(item.name).font(.system(size: 12, weight: .medium))
                Spacer(minLength: 4)
                if item.loading && item.latency == nil { ProgressView().controlSize(.mini) }
                else {
                    Text(item.latency.flatMap { $0 >= 0 ? String($0) : nil } ?? "—")
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .monospacedDigit().foregroundStyle(Color.latency(item.latency))
                    Text("ms").font(.system(size: 11)).foregroundStyle(.secondary)
                }
        }.padding(.vertical, 10)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(item.name): \(status)")
            .help("\(status) · HTTPS response time, checked automatically every 30 seconds.")
    }
}

struct OverviewTrafficPoint: Identifiable {
    var id: Date { time }
    let time: Date
    let download: Double
    let upload: Double
}

struct OverviewTrafficCard: View {
    let points: [OverviewTrafficPoint]
    let download: String
    let upload: String
    @State private var selectedTime: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private var selectedPoint: OverviewTrafficPoint? {
        guard let selectedTime else { return nil }
        return points.min { abs($0.time.timeIntervalSince(selectedTime)) < abs($1.time.timeIntervalSince(selectedTime)) }
    }

    var body: some View {
        VStack(spacing: 18) {
            lane("Download", value: selectedPoint.map { format($0.download) } ?? download,
                 color: .seriesDown, uploadLane: false)
            Rectangle().fill(DS.line).frame(height: 0.5)
            lane("Upload", value: selectedPoint.map { format($0.upload) } ?? upload,
                 color: .seriesUp, uploadLane: true)
            HStack {
                Text("60s ago")
                Spacer()
                Text(selectedPoint?.time.formatted(date: .omitted, time: .standard) ?? "Now")
            }.font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    private func lane(_ title: String, value: String, color: Color, uploadLane: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                HStack(spacing: 6) {
                    DashboardSymbol(name: uploadLane ? "arrow.up" : "arrow.down")
                    Text(title).font(.system(size: 12, weight: .medium))
                }.foregroundStyle(color)
                speed(value)
                Spacer()
            }
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || scenePhase != .active)) { timeline in
            Chart {
                ForEach(points) { point in
                    let value = uploadLane ? point.upload : point.download
                    AreaMark(x: .value("Time", point.time), y: .value("Bytes/s", value))
                        .foregroundStyle(LinearGradient(colors: [color.opacity(0.09), color.opacity(0.005)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Time", point.time), y: .value("Bytes/s", value))
                        .foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 1.4)).interpolationMethod(.monotone)
                }
                if let selectedTime {
                    RuleMark(x: .value("Time", selectedTime)).foregroundStyle(Color.secondary.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                }
            }
            .chartLegend(.hidden).chartXSelection(value: $selectedTime).chartXAxis(.hidden)
            .chartPlotStyle { plot in plot.clipped() }
            .chartXScale(domain: timeline.date.addingTimeInterval(-60)...timeline.date)
            .chartYScale(domain: 0...max(1024, points.map { uploadLane ? $0.upload : $0.download }.max() ?? 1024) * 1.15)
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 2)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4])).foregroundStyle(DS.line)
                    AxisValueLabel {
                        if let bytes = value.as(Double.self) { Text(format(bytes)).font(.system(size: 10)).foregroundStyle(.secondary) }
                    }
                }
            }
            .animation(.easeInOut(duration: 0.35), value: points.map { uploadLane ? $0.upload : $0.download }.max())
            }
            .frame(minHeight: 40, maxHeight: .infinity)
            .accessibilityLabel("\(title) bytes per second. Independently scaled, last 60 seconds.")
        }
    }

    private func format(_ value: Double) -> String {
        guard value > 0 else { return "0 B/s" }
        return ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file) + "/s"
    }

    private func speed(_ value: String) -> some View {
        let parts = value.split(separator: " ", maxSplits: 1)
        return HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(parts.first.map(String.init) ?? "—")
                .font(.system(size: 20, weight: .medium, design: .rounded)).monospacedDigit()
            if parts.count > 1 { Text(String(parts[1])).font(.system(size: 11)).foregroundStyle(.secondary) }
        }
    }
}

/// All dashboard symbols share the same optical box and stroke weight.
private struct DashboardSymbol: View {
    let name: String
    var body: some View {
        Image(systemName: name)
            .font(.system(size: 13, weight: .regular))
            .symbolRenderingMode(.monochrome)
            .frame(width: 16, height: 16)
            .accessibilityHidden(true)
    }
}
