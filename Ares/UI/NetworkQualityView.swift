import SwiftUI
import Charts
import SubscriptionKit

struct NetworkQualityView: View {
    var embedded = false
    @ObservedObject private var service = NetworkQualityService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var target = "gstatic"
    @State private var manual = ""
    @State private var policies = false
    @State private var confirmingReset = false
    private var samples: [NetworkQuality.Sample] { service.window.samples[target] ?? [] }
    private var selected: ProxyGroup? { service.groups.first { $0.name == service.group } }
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            if !embedded { HStack {
                Text("Quality").font(DS.Typography.secondary.weight(.semibold))
                Spacer(); Button("Done") { dismiss() }.controlSize(.small)
            } }
            WorkspaceControls {
                Picker("Probe", selection: $target) {
                    ForEach(NetworkQualityService.targets) { Text($0.name).tag($0.id) }
                    Text("DNS").tag("dns")
                }.pickerStyle(.segmented).labelsHidden()
            } actions: {
                Toggle("Monitor", isOn: Binding(get: { service.enabled }, set: service.setEnabled)).toggleStyle(.switch)
                Menu {
                    Button("Reset Measurements…", role: .destructive) { confirmingReset = true }
                } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("Quality actions")
            }
            WorkspaceControls {
                HStack(spacing: DS.Space.md) {
                    Picker("Policy", selection: Binding(get: { service.group }, set: { service.configure(group: $0, interval: service.interval) })) {
                        Text("Choose policy").tag("")
                        if !service.group.isEmpty && selected == nil { Text(service.group + " · unavailable").tag(service.group) }
                        ForEach(service.groups) { Text($0.name).tag($0.name) }
                    }.frame(width: 230).help(service.group)
                    Picker("Interval", selection: Binding(get: { service.interval }, set: { service.configure(group: service.group, interval: $0) })) {
                        Text("30 s").tag(30); Text("1 min").tag(60); Text("5 min").tag(300)
                    }.fixedSize()
                }
            } actions: {
                WorkspaceAction(title: "Policies", symbol: "slider.horizontal.3") {
                    if embedded { AppState.shared.selection = .policies } else { policies = true }
                }
                Image(systemName: "info.circle").foregroundStyle(.secondary)
                    .help("HTTPS probes use the selected policy. DNS probes use the configured resolver rules. Controller errors are excluded from success rates.")
                    .accessibilityLabel("How probes work")
            }
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
                        Button("Resume · " + name) { Task { await service.resumeAutomatic(group: name) } }.controlSize(.small)
                    }
                }
            }
            if let selected, selected.supportsManualSelection {
                HStack {
                    Text("Route").font(DS.Typography.secondary)
                    Picker("Route", selection: $manual) {
                        Text("Choose member").tag("")
                        ForEach(selected.all, id: \.self) { Text($0).tag($0) }
                    }.labelsHidden().frame(maxWidth: 280, alignment: .leading)
                    Button("Select") { Task { await service.select(member: manual) } }.disabled(!selected.all.contains(manual))
                    Spacer()
                    Image(systemName: "info.circle").foregroundStyle(.secondary).help("Changes only this policy group")
                }.controlSize(.small)
            }
            DSCard(padding: DS.Space.lg) { metrics }
            Chart(samples) { sample in
                if let latency = sample.milliseconds {
                    PointMark(x: .value("Time", sample.date), y: .value("Milliseconds", latency))
                        .foregroundStyle(Color.accentColor).symbolSize(16)
                } else {
                    RuleMark(x: .value("Failure", sample.date)).foregroundStyle(Color.statusBad.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }.chartYAxisLabel("ms").frame(height: 180)
            HStack {
                Text(samples.last.map { "Last: " + $0.outcome + " · " + $0.date.formatted(date: .omitted, time: .standard) } ?? "No samples yet")
                Spacer()
                Text("Latest 120 samples")
            }.font(DS.Typography.metadata).foregroundStyle(.secondary)
            HStack {
                Text("Route changes").font(DS.Typography.secondary.weight(.medium)); Spacer()
                Text("10 sec · This session").help("Core automatic selection continues with this page closed. Intermediate switches between observations may be missed.").font(DS.Typography.metadata).foregroundStyle(.secondary)
            }
            Table(service.window.events) {
                TableColumn("Time") { Text($0.date.formatted(date: .omitted, time: .standard)) }.width(75)
                TableColumn("Before → After") { Text($0.before.path.joined(separator: " → ") + "  /  " + $0.after.path.joined(separator: " → ")).lineLimit(2) }
                TableColumn("Evidence") { Text($0.reason).lineLimit(2) }
            }.font(DS.Typography.metadata).frame(height: 180)
            if let error = service.error { Text(error).font(DS.Typography.metadata).foregroundStyle(Color.statusBad) }
        }.padding(.horizontal, DS.Space.lg).padding(.top, DS.Space.pageTop).padding(.bottom, DS.Space.lg).frame(minWidth: embedded ? 0 : 880).background(DS.canvas).scrollIndicators(.never, axes: [.horizontal, .vertical])
            .task { service.start(); await service.readGroups() }
            .onChange(of: service.group) { _, _ in manual = "" }
            .confirmationDialog("Reset this session’s measurements?", isPresented: $confirmingReset) {
                Button("Reset Measurements", role: .destructive) { service.reset() }
            }
            .sheet(isPresented: $policies, onDismiss: { Task { await service.readGroups() } }) { PolicyGroupsView().environmentObject(ClashController.shared) }
    }
    private var metrics: some View {
        let value = NetworkQuality.Summary(samples)
        return HStack(spacing: 16) {
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
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
