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
struct DashboardComposition<Traffic: View, Controls: View, Details: View, Advanced: View>: View {
    let runtime: String
    let version: String
    let status: DSStatus
    let api: String
    @ViewBuilder var traffic: () -> Traffic
    @ViewBuilder var controls: () -> Controls
    @ViewBuilder var details: () -> Details
    @ViewBuilder var advanced: () -> Advanced

    var body: some View {
        GeometryReader { geometry in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    if geometry.size.width >= 850 {
                        HStack(alignment: .top, spacing: 28) {
                            traffic().frame(maxWidth: .infinity)
                            Rectangle().fill(DS.line).frame(width: 0.5)
                            controls().frame(width: 230)
                        }.fixedSize(horizontal: false, vertical: true)
                    } else {
                        VStack(spacing: 28) {
                            traffic()
                            controls()
                        }
                    }
                    Rectangle().fill(DS.line).frame(height: 0.5).padding(.vertical, 24)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 24, alignment: .top), count: geometry.size.width >= 850 ? 3 : 2), alignment: .leading, spacing: 24) {
                        details()
                    }
                    .environment(\.flatSurfaces, true)
                    Rectangle().fill(DS.line).frame(height: 0.5).padding(.top, 24).padding(.bottom, 18)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 28, alignment: .top), count: geometry.size.width >= 850 ? 3 : 2), alignment: .leading, spacing: 28) {
                        advanced()
                    }
                    .environment(\.flatSurfaces, true)
                    HStack(spacing: 7) {
                        Circle().fill(status.color).frame(width: 6, height: 6)
                        Text(runtime).fontWeight(.medium)
                        Text("·").foregroundStyle(.tertiary)
                        Text(version).foregroundStyle(.secondary)
                        Spacer()
                        Text(api).foregroundStyle(.secondary).monospacedDigit()
                    }
                    .font(DS.Typography.metadata)
                    .padding(.top, 24)

                }
                .padding(28)
                .frame(maxWidth: 1240)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .top)
            }
        }
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
        VStack(alignment: .leading, spacing: 21) {
            VStack(spacing: 19) {
                DSToggleRow(icon: "globe", title: "System proxy", tint: .accentColor, isOn: $systemProxy)
                DSToggleRow(icon: "bolt.shield", title: "TUN mode", tint: .accentColor, isOn: $tun)
                DSToggleRow(icon: "viewfinder", title: "MITM", tint: .accentColor, isOn: $interception)
            }
            Divider().opacity(0.5)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    modeButton("Rule", symbol: "list.bullet.indent", index: 0)
                    modeButton("Global", symbol: "globe", index: 1)
                    modeButton("Direct", symbol: "arrow.up.right", index: 2)
                }
            }
            Label("\(snapshot.connections.map(String.init) ?? "—") connections", systemImage: "arrow.left.arrow.right")
                .font(DS.Typography.metadata).foregroundStyle(.secondary)
        }
        .disabled(busy)
    }

    private func modeButton(_ title: String, symbol: String, index: Int) -> some View {
        Button { mode = index } label: {
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 18, weight: .light))
                Text(title).font(DS.Typography.metadata.weight(mode == index ? .medium : .regular))
            }
            .foregroundStyle(mode == index ? Color.accentColor : .secondary)
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(mode == index ? Color.accentColor.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) mode")
        .accessibilityAddTraits(mode == index ? .isSelected : [])
    }
}

struct OverviewTrafficPoint: Identifiable {
    let id: Int
    let time: Date
    let download: Double
    let upload: Double
}

struct OverviewTrafficCard: View {
    let points: [OverviewTrafficPoint]
    let download: String
    let upload: String
    @State private var selectedTime: Date?

    private var selectedPoint: OverviewTrafficPoint? {
        guard let selectedTime else { return nil }
        return points.min { abs($0.time.timeIntervalSince(selectedTime)) < abs($1.time.timeIntervalSince(selectedTime)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 36) {
                speed("Download", value: selectedPoint.map { format($0.download) } ?? download, color: .seriesDown, icon: "arrow.down")
                speed("Upload", value: selectedPoint.map { format($0.upload) } ?? upload, color: .seriesUp, icon: "arrow.up")
                Spacer(minLength: 0)
            }
            Chart {
                ForEach(points) { point in
                    AreaMark(x: .value("Time", point.time), y: .value("Download", point.download))
                        .foregroundStyle(LinearGradient(colors: [Color.seriesDown.opacity(0.14), Color.seriesDown.opacity(0.01)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Time", point.time), y: .value("Bytes/s", point.download), series: .value("Direction", "Download"))
                        .foregroundStyle(Color.seriesDown).lineStyle(StrokeStyle(lineWidth: 1.7)).interpolationMethod(.monotone)
                    LineMark(x: .value("Time", point.time), y: .value("Bytes/s", point.upload), series: .value("Direction", "Upload"))
                        .foregroundStyle(Color.seriesUp).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 3])).interpolationMethod(.monotone)
                }
                if let selectedTime {
                    RuleMark(x: .value("Time", selectedTime)).foregroundStyle(Color.secondary.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                }
            }
            .chartLegend(.hidden)
            .chartXSelection(value: $selectedTime)
            .chartXAxis(.hidden)
            .chartYScale(domain: 0...max(1024, points.map { max($0.download, $0.upload) }.max() ?? 1024) * 1.15)
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4])).foregroundStyle(DS.line)
                    AxisValueLabel {
                        if let bytes = value.as(Double.self) {
                            Text(format(bytes)).font(DS.Typography.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(height: 176)
            .accessibilityLabel("Upload and download traffic over the last 60 seconds")
            HStack {
                Text("60s ago")
                Spacer()
                Text(selectedPoint?.time.formatted(date: .omitted, time: .standard) ?? "Now")
            }
            .font(DS.Typography.caption).foregroundStyle(.secondary)
        }
    }

    private func format(_ value: Double) -> String {
        guard value > 0 else { return "0 B/s" }
        return ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file) + "/s"
    }

    private func speed(_ title: String, value: String, color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: icon).font(DS.Typography.metadata).foregroundStyle(color)
            Text(value).font(DS.Typography.metric).monospacedDigit()
        }
    }
}
