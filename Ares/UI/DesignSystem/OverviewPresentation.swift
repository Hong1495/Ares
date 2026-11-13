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
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 24) {
                    controls().fixedSize(horizontal: false, vertical: true)
                    traffic().frame(height: min(230, max(150, geometry.size.height * 0.25)))
                    details().fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .top)
                }
                .padding(.horizontal, 28).padding(.vertical, 20)
                .frame(minHeight: geometry.size.height, alignment: .top)
            }.scrollIndicators(.never, axes: [.horizontal, .vertical])
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
        OverviewRoutingModePicker(selection: $mode)
    }

    private func capability(_ title: String, icon: String, value: Binding<Bool>) -> some View {
        Toggle(isOn: value) {
            HStack(spacing: 7) {
                DashboardSymbol(name: icon).foregroundStyle(.secondary)
                Text(title).font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.primary)
        }.toggleStyle(OverviewRecessedToggleStyle()).tint(DS.accent)
            .accessibilityLabel(title).accessibilityValue(value.wrappedValue ? "On" : "Off")
            .help("\(value.wrappedValue ? "Disable" : "Enable") \(title)")
    }
}

/// Shared raised surface for the dashboard's discrete controls.
private struct OverviewRaisedThumb: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Capsule()
            .fill(LinearGradient(colors: scheme == .dark
                ? [Color(nsColor: .init(white: 0.30, alpha: 1)), Color(nsColor: .init(white: 0.22, alpha: 1))]
                : [.white, Color(nsColor: .init(white: 0.96, alpha: 1))], startPoint: .top, endPoint: .bottom))
            .overlay { Capsule().strokeBorder(LinearGradient(colors: [.white.opacity(scheme == .dark ? 0.24 : 0.9), Color.black.opacity(0.10)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.75) }
            .shadow(color: .black.opacity(scheme == .dark ? 0.30 : 0.13), radius: 2, x: 0, y: 1)
    }
}

private struct OverviewRecessedToggleStyle: ToggleStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.label
            Button { configuration.isOn.toggle() } label: {
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.075))
                        .overlay { Capsule().strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5) }
                    OverviewRaisedThumb().frame(width: 38, height: 26)
                        .offset(x: configuration.isOn ? 2 : 40)
                        .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: configuration.isOn)
                    HStack(spacing: 0) {
                        Text("On").foregroundStyle(configuration.isOn ? DS.accent : Color.secondary).frame(width: 38)
                        Text("Off").foregroundStyle(configuration.isOn ? Color.secondary : Color.primary).frame(width: 38)
                    }.font(.system(size: 10, weight: .medium))
                        .frame(width: 76).padding(.horizontal, 2)
                }.frame(width: 80, height: 30).contentShape(Capsule())
            }.buttonStyle(.plain)
                .accessibilityLabel(configuration.isOn ? "On" : "Off")
        }.opacity(isEnabled ? 1 : 0.5)
    }
}

/// Three discrete routing modes, connected by a horizontal rail.
/// Buttons retain native focus and keyboard activation; position never implies a numeric value.
struct OverviewRoutingModePicker: View {
    @Binding var selection: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered: Int?
    private let titles = ["Rule", "Global", "Direct"]
    private let symbols = ["slider.horizontal.3", "globe", "arrow.up.right"]
    private let hints = ["Follow routing rules", "Use the global proxy group", "Connect directly"]

    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(0..<2) { index in
                Capsule().fill(Color.primary.opacity(0.22))
                    .frame(width: 24, height: 2)
                    .offset(x: 88 + CGFloat(index) * 112)
            }
            OverviewRaisedThumb()
                .frame(width: 88, height: 30)
                .offset(x: CGFloat(selection) * 112)
                .animation(reduceMotion ? nil : .smooth(duration: 0.24), value: selection)
            HStack(spacing: 24) {
                ForEach(0..<3) { index in
                    Button { selection = index } label: {
                        HStack(spacing: 7) {
                            Image(systemName: symbols[index])
                                .font(.system(size: 13, weight: .regular))
                                .symbolRenderingMode(.monochrome)
                                .foregroundStyle(selection == index ? DS.accent : Color.secondary)
                                .frame(width: 16, height: 16)
                            Text(titles[index]).font(.system(size: 12, weight: selection == index ? .medium : .regular))
                                .foregroundStyle(selection == index ? Color.primary : Color.secondary)
                        }.frame(width: 88, height: 30)
                            .background {
                                if selection != index {
                                    Capsule().fill(DS.canvas)
                                    Capsule().fill(hovered == index ? DS.soft : Color.clear)
                                }
                            }.contentShape(Capsule())
                    }.buttonStyle(.plain)
                        .onHover { hovered = $0 ? index : nil }
                        .accessibilityLabel(titles[index])
                        .accessibilityValue(selection == index ? "Selected" : "Not selected")
                        .accessibilityAddTraits(selection == index ? [.isSelected] : [])
                        .help(hints[index])
                }
            }
        }.frame(width: 312, height: 30)
            .accessibilityElement(children: .contain).accessibilityLabel("Routing mode")
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
        VStack(spacing: 12) {
            HStack(spacing: 24) {
                lane("Download", value: selectedPoint.map { format($0.download) } ?? download,
                     color: .seriesDown, uploadLane: false)
                Rectangle().fill(DS.line).frame(width: 0.5)
                lane("Upload", value: selectedPoint.map { format($0.upload) } ?? upload,
                     color: .seriesUp, uploadLane: true)
            }
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

/// Compact overview of existing workflows; all values and destinations are supplied by the owner.
struct OverviewWorkspaceSummary: View {
    struct ProcessRow: Identifiable {
        let id: String
        let name: String
        let connections: Int
    }
    struct Probe: Identifiable {
        let id: String
        let name: String
        let success: String
        let latency: Int?
        let samples: [Int?]
    }
    struct ConfigurationSummary {
        let value: String
        let unit: String
        let rows: [String]
        let status: String
    }
    var probes: [Probe] = []
    var applications = ConfigurationSummary(value: "—", unit: "rules", rows: [], status: "Unavailable")
    var policies = ConfigurationSummary(value: "—", unit: "groups", rows: [], status: "Unavailable")
    var scenes = ConfigurationSummary(value: "—", unit: "saved", rows: [], status: "Unavailable")
    let processes: [ProcessRow]
    let activityStatus: String
    let connections: Int?
    let processCount: Int?
    let qualityStatus: String
    let qualityGroup: String
    let route: String
    let openActivity: () -> Void
    let openApplications: () -> Void
    let openQuality: () -> Void
    let openPolicies: () -> Void
    let openScenes: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 24) {
                    activity.frame(minWidth: 270, maxWidth: .infinity)
                    quality.frame(minWidth: 340, maxWidth: .infinity)
                }
                VStack(spacing: 24) { activity; quality }
            }
            configurationGrid
        }
    }

    // Shared rows keep headings, values and footers aligned even when content differs.
    private var configurationGrid: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 24, verticalSpacing: 12) {
            GridRow {
                heading("Applications", action: openApplications)
                heading("Policies", action: openPolicies)
                heading("Scenes", action: openScenes)
            }
            GridRow {
                configurationMetric(applications)
                configurationMetric(policies)
                configurationMetric(scenes)
            }
            GridRow {
                configurationRows(applications)
                configurationRows(policies)
                configurationRows(scenes)
            }
            GridRow {
                configurationStatus(applications)
                configurationStatus(policies)
                configurationStatus(scenes)
            }
        }
        .padding(.top, 16)
        .overlay(alignment: .top) { Rectangle().fill(DS.line).frame(height: 0.5) }
    }

    private var activity: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("Activity", action: openActivity)
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                metric(connections.map(String.init) ?? "—", "connections").help("Active connections, excluding Ares and its core")
                metric(processCount.map(String.init) ?? "—", "sources")
                    .help("Grouped by application or executable; unidentified traffic is grouped by source address.")
            }
            if processes.isEmpty {
                Text(activityStatus).font(DS.Typography.metadata).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(processes) { row in
                            HStack(spacing: 12) {
                                Text(row.name).font(DS.Typography.secondary).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                                GeometryReader { proxy in
                                    Capsule().fill(DS.accent.opacity(0.35))
                                        .frame(width: proxy.size.width * CGFloat(row.connections) / CGFloat(max(connections ?? 0, 1)))
                                }.frame(width: 64, height: 3)
                                Text(String(row.connections)).font(DS.Typography.secondary.monospacedDigit()).frame(width: 30, alignment: .trailing)
                            }.help("\(row.name): \(row.connections) active connections")
                        }
                    }
                }.frame(height: min(210, CGFloat(processes.count) * 28 - 12)).scrollIndicators(.never)
            }

        }.padding(.top, 16).overlay(alignment: .top) { Rectangle().fill(DS.line).frame(height: 0.5) }
    }
    private var quality: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("Network Quality", action: openQuality)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(qualityGroup).font(DS.Typography.secondary.weight(.medium)).lineLimit(1)
                Spacer()
                Text(qualityStatus).font(DS.Typography.metadata).foregroundStyle(.secondary).lineLimit(1).help(qualityStatus)
            }.frame(height: 24)
            VStack(spacing: 12) {
                ForEach(probes) { probe in
                    HStack(spacing: 10) {
                        Text(probe.name).font(DS.Typography.secondary).frame(width: 64, alignment: .leading)
                        Chart {
                            ForEach(probe.samples.indices, id: \.self) { index in
                                if let value = probe.samples[index] {
                                    LineMark(x: .value("Sample", index), y: .value("ms", value),
                                             series: .value("Segment", probe.samples.prefix(index).filter { $0 == nil }.count))
                                        .foregroundStyle(DS.accent).lineStyle(StrokeStyle(lineWidth: 1))
                                    PointMark(x: .value("Sample", index), y: .value("ms", value)).foregroundStyle(DS.accent).symbolSize(5)
                                } else {
                                    RuleMark(x: .value("Failure", index)).foregroundStyle(Color.statusBad.opacity(0.5))
                                }
                            }
                        }.chartXAxis(.hidden).chartYAxis(.hidden).frame(height: 28)
                            .accessibilityLabel(probe.name + " · latest probe samples")
                        Text(probe.success).font(DS.Typography.metadata.monospacedDigit()).frame(width: 48, alignment: .trailing)
                        Text(probe.latency.map { "\($0) ms" } ?? "—").font(DS.Typography.secondary.monospacedDigit())
                            .foregroundStyle(Color.latency(probe.latency)).frame(width: 62, alignment: .trailing)
                    }.help("Success rate · Latest measured response · Up to 120 samples")
                }
                Text(route).font(DS.Typography.metadata).foregroundStyle(.secondary).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            }

        }.padding(.top, 16).overlay(alignment: .top) { Rectangle().fill(DS.line).frame(height: 0.5) }
    }
    private func heading(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).font(DS.Typography.secondary.weight(.medium))
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(.secondary)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).help("Open " + title)
    }
    private func metric(_ value: String, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value).font(.system(size: 20, weight: .medium, design: .rounded)).monospacedDigit()
            Text(label).font(DS.Typography.metadata).foregroundStyle(.secondary)
        }
    }
    private func configurationMetric(_ summary: ConfigurationSummary) -> some View {
        metric(summary.value, summary.unit).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func configurationRows(_ summary: ConfigurationSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(summary.rows.enumerated()), id: \.offset) { _, row in
                Text(row).font(DS.Typography.secondary).lineLimit(1).truncationMode(.middle).help(row)
            }
            if summary.rows.isEmpty { Text("—").font(DS.Typography.secondary).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func configurationStatus(_ summary: ConfigurationSummary) -> some View {
        Text(summary.status).font(DS.Typography.metadata).foregroundStyle(.secondary)
            .lineLimit(2).help(summary.status).frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
