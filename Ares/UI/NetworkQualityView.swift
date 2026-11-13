import SwiftUI
import Charts
import SubscriptionKit

struct NetworkQualityView: View {
    @ObservedObject private var service = NetworkQualityService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var target = "gstatic"
    @State private var manual = ""
    @State private var policies = false
    private var samples: [NetworkQuality.Sample] { service.window.samples[target] ?? [] }
    private var selected: ProxyGroup? { service.groups.first { $0.name == service.group } }
    var body: some View {
        VStack(spacing: DS.Space.lg) {
            HStack {
                Text("Network Quality").font(DS.Typography.secondary.weight(.semibold))
                Spacer()
                Toggle("Monitor", isOn: Binding(get: { service.enabled }, set: service.setEnabled)).toggleStyle(.switch).controlSize(.mini)
                Button("Done") { dismiss() }.controlSize(.small)
            }
            HStack {
                Picker("Policy", selection: Binding(get: { service.group }, set: { service.configure(group: $0, interval: service.interval) })) {
                    Text("Choose group").tag("")
                    if !service.group.isEmpty && selected == nil { Text(service.group + " · unavailable").tag(service.group) }
                    ForEach(service.groups) { Text($0.name).tag($0.name) }
                }.frame(maxWidth: 330)
                Picker("Every", selection: Binding(get: { service.interval }, set: { service.configure(group: service.group, interval: $0) })) {
                    Text("30 sec").tag(30); Text("1 min").tag(60); Text("5 min").tag(300)
                }.frame(width: 155)
                Spacer()
                Button("Policies") { policies = true }
                Button { service.reset() } label: { Image(systemName: "arrow.counterclockwise") }.help("Reset this session’s measurements")
            }.controlSize(.small)
            HStack {
                Text(service.status).font(DS.Typography.metadata).foregroundStyle(.secondary)
                Spacer()
                if let date = service.observedAt { Text(date.formatted(date: .omitted, time: .standard)).font(DS.Typography.metadata).foregroundStyle(.secondary) }
            }
            if let route = service.window.route {
                HStack {
                    Text(route.path.joined(separator: " → ")).font(DS.Typography.secondary).lineLimit(2).textSelection(.enabled)
                    Spacer()
                    ForEach(route.path.filter { name in service.groups.contains { $0.name == name && $0.supportsAutomaticSelection && $0.manualSelection != nil } }, id: \.self) { name in
                        Button("Resume " + name) { Task { await service.resumeAutomatic(group: name) } }.controlSize(.small)
                    }
                }
            }
            if let selected, selected.supportsManualSelection {
                HStack {
                    Picker("Manual override", selection: $manual) {
                        Text("Choose member").tag("")
                        ForEach(selected.all, id: \.self) { Text($0).tag($0) }
                    }.frame(maxWidth: 420)
                    Button("Select") { Task { await service.select(member: manual) } }.disabled(!selected.all.contains(manual))
                    Spacer()
                    Text("Only changes this group").font(DS.Typography.metadata).foregroundStyle(.secondary)
                }.controlSize(.small)
            }
            Picker("Probe", selection: $target) {
                ForEach(NetworkQualityService.targets) { Text($0.name).tag($0.id) }; Text("DNS").tag("dns")
            }.pickerStyle(.segmented).controlSize(.small)
            metrics
            Chart(samples) { sample in
                if let latency = sample.milliseconds {
                    PointMark(x: .value("Time", sample.date), y: .value("Milliseconds", latency))
                        .foregroundStyle(Color.accentColor).symbolSize(16)
                } else {
                    RuleMark(x: .value("Failure", sample.date)).foregroundStyle(Color.statusBad.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }.chartYAxisLabel("ms").frame(minHeight: 110, idealHeight: 145, maxHeight: 180)
            HStack {
                Text(samples.last.map { "Last: " + $0.outcome + " · " + $0.date.formatted(date: .omitted, time: .standard) } ?? "No measured samples yet")
                Spacer()
                Text("Latest 120 samples / target")
            }.font(DS.Typography.metadata).foregroundStyle(.secondary)
            Text(target == "dns" ? "Resolver API response time for www.gstatic.com · cache may apply. DNS uses configured resolver rules, independently of the selected policy." : "HTTPS probes through the selected policy, even if system proxy is off. Success rate describes these targets only. Red markers are confirmed probe failures; controller errors are excluded. Variation is the mean change between adjacent successful samples.")
                .font(DS.Typography.metadata).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                Text("Route changes").font(DS.Typography.secondary.weight(.medium)); Spacer()
                Text("Observed every 10 sec · session only").font(DS.Typography.metadata).foregroundStyle(.secondary)
            }
            Table(service.window.events) {
                TableColumn("Time") { Text($0.date.formatted(date: .omitted, time: .standard)) }.width(75)
                TableColumn("Before → After") { Text($0.before.path.joined(separator: " → ") + "  /  " + $0.after.path.joined(separator: " → ")).lineLimit(2) }
                TableColumn("Evidence") { Text($0.reason).lineLimit(2) }
            }.font(DS.Typography.metadata).frame(minHeight: 110)
            Text("Automatic selection and fallback run in mihomo, including when this window is closed. Intermediate switches between observations may be missed. Enabling monitoring sends periodic requests to the listed services.")
                .font(DS.Typography.metadata).foregroundStyle(.secondary)
            if let error = service.error { Text(error).font(DS.Typography.metadata).foregroundStyle(Color.statusBad) }
        }.padding(DS.Space.lg).frame(minWidth: 880, minHeight: 720).background(DS.canvas).scrollIndicators(.never, axes: [.horizontal, .vertical])
            .task { service.start(); await service.readGroups() }
            .onChange(of: service.group) { _, _ in manual = "" }
            .sheet(isPresented: $policies, onDismiss: { Task { await service.readGroups() } }) { PolicyGroupsView().environmentObject(ClashController.shared) }
    }
    private var metrics: some View {
        let value = NetworkQuality.Summary(samples)
        return HStack(spacing: 28) {
            metric("Success", value.successPercent.map { String(format: "%.1f%%", $0) } ?? "—")
            metric("Median", value.median.map { "\($0) ms" } ?? "—")
            metric("P95", value.p95.map { "\($0) ms" } ?? "—")
            metric("Variation", value.variation.map { "\($0) ms" } ?? "—")
            metric("Samples", String(value.attempts))
            metric("Unavailable", String(service.window.unavailable[target, default: 0]))
            Spacer()
        }
    }
    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(size: 18, weight: .medium, design: .rounded)).monospacedDigit()
            Text(title).font(DS.Typography.metadata).foregroundStyle(.secondary)
        }
    }
}
