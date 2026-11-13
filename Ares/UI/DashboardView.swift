import SwiftUI
import SubscriptionKit

struct DashboardView: View {
    var body: some View {
        VStack(spacing: 0) {
            DashboardComposition {
                TrafficCard()
            } controls: {
                ControlCenterCard()
            } details: {
                DashboardWorkspaceSummary()
            }
        }
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                DashboardIdentityView().padding(.leading, 16)
            }.aresUnframed()
        }
    }
}

// MARK: - Control center

private struct ControlCenterCard: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var clashViewModel: ClashViewModel
    @EnvironmentObject private var clashController: ClashController

    private var coreStatus: DSStatus {
        switch clashViewModel.runtimeState {
        case .running, .apiReady: return .good
        case .launching, .processRunning, .stopping: return .warning
        case .failed: return .critical
        case .stopped: return .idle
        }
    }

    private var headline: String {
        if appState.systemProxyEnabled && clashViewModel.isRunning { return "Protected" }
        if appState.tunEnabled && clashViewModel.isRunning { return "TUN active" }
        return clashViewModel.runtimeState.title
    }

    private var subheadline: String {
        if appState.systemProxyEnabled && clashViewModel.isRunning {
            return "System traffic is routed through Ares"
        }
        if appState.tunEnabled && clashViewModel.isRunning {
            return "All traffic is captured at the network layer"
        }
        return "Traffic is not being proxied"
    }

    var body: some View {
        OverviewConnectionCard(
            snapshot: OverviewSnapshot(
                title: headline, subtitle: subheadline, status: coreStatus,
                runtime: clashViewModel.runtimeState.title,
                node: clashController.primaryNodeName ?? "No node selected",
                latency: clashController.primaryLatency,
                connections: appState.activeConnectionsCount,
                download: "", upload: ""
            ),
            systemProxy: Binding(get: { appState.systemProxyEnabled }, set: { _ in Task { await appState.toggleSystemProxy() } }),
            tun: Binding(get: { appState.tunEnabled }, set: { _ in appState.toggleTUN() }),
            interception: Binding(get: { appState.mitmEnabled }, set: { _ in appState.toggleMITM() }),
            mode: Binding(
                get: { [ClashConfig.Mode.rule, .global, .direct].firstIndex(of: appState.currentMode) ?? 0 },
                set: { index in Task { await appState.setMode([.rule, .global, .direct][index]) } }
            ),
            busy: appState.isPerformingNetworkOperation || clashViewModel.isToggling
        )
    }
}

// MARK: - Traffic

private struct TrafficCard: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var model = TrafficGraphViewModel()

    var body: some View {
        OverviewTrafficCard(
            points: model.dataPoints.map { point in
                OverviewTrafficPoint(time: point.time, download: Double(point.download), upload: Double(point.upload))
            },
            download: Self.formatSpeed(model.currentDownload),
            upload: Self.formatSpeed(model.currentUpload)
        )
        .task {
            await Task.yield()
            model.startMonitoring()
        }
        .onDisappear { model.stopMonitoring() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                model.startMonitoring()
            } else if newPhase == .background {
                model.stopMonitoring()
            }
        }
    }

    @Environment(\.scenePhase) private var scenePhase

    static func formatSpeed(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0 B/s" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes) + "/s"
    }
}


private struct DashboardWorkspaceSummary: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var quality = NetworkQualityService.shared
    @ObservedObject private var controller = ClashController.shared
    @ObservedObject private var profiles = ProfileService.shared
    @ObservedObject private var automation = SceneAutomationService.shared
    @State private var applications = OverviewWorkspaceSummary.ConfigurationSummary(value: "—", unit: "rules", rows: [], status: "Loading")
    @State private var policies = OverviewWorkspaceSummary.ConfigurationSummary(value: "—", unit: "groups", rows: [], status: "Loading")
    @State private var scenes = OverviewWorkspaceSummary.ConfigurationSummary(value: "—", unit: "saved", rows: [], status: "Loading")
    @State private var lastConfigurationRead = Date.distantPast
    @State private var rows: [OverviewWorkspaceSummary.ProcessRow] = []
    @State private var connectionCount: Int?
    @State private var processCount: Int?
    @State private var activityStatus = "Waiting for activity"
    @Environment(\.scenePhase) private var phase

    var body: some View {
        OverviewWorkspaceSummary(probes: probes, applications: applications, policies: policies, scenes: sceneSummary, processes: rows, activityStatus: activityStatus,
            connections: connectionCount, processCount: processCount,
            qualityStatus: quality.enabled ? quality.status : "Monitoring is off · Open Network Quality to start",
            qualityGroup: quality.group.isEmpty ? "No monitored policy" : quality.group,
            route: quality.enabled ? quality.window.route?.path.joined(separator: " → ") ?? "Waiting for measured results" : "Periodic HTTPS and DNS measurements",
            openActivity: { appState.selection = .connections },
            openApplications: { appState.selection = .applications },
            openQuality: { appState.selection = .quality },
            openPolicies: { appState.selection = .policies },
            openScenes: { appState.selection = .scenes })
        .task(id: "\(phase)-\(profiles.activeProfileRevision)") {
            guard phase == .active else { return }
            applications = .init(value: "—", unit: "rules", rows: [], status: "Loading")
            policies = .init(value: "—", unit: "groups", rows: [], status: "Loading")
            scenes = .init(value: "—", unit: "saved", rows: [], status: "Loading")
            lastConfigurationRead = .distantPast
            while !Task.isCancelled {
                if Date().timeIntervalSince(lastConfigurationRead) >= 30 { await refreshConfiguration() }
                await refresh()
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
            }
        }
        .onChange(of: controller.runtimeGeneration) { _, _ in
            rows = []; connectionCount = nil; processCount = nil
            activityStatus = "Waiting for current runtime"
        }
    }
    private var probes: [OverviewWorkspaceSummary.Probe] {
        let targets = NetworkQualityService.targets.map { ($0.id, $0.name) } + [("dns", "DNS")]
        return targets.map { id, name in
            let samples = quality.enabled ? quality.window.samples[id] ?? [] : []
            let summary = NetworkQuality.Summary(samples)
            return .init(id: id, name: name, success: summary.successPercent.map { String(format: "%.1f%%", $0) } ?? "—",
                         latency: samples.last?.milliseconds, samples: samples.map(\.milliseconds))
        }
    }
    private var sceneSummary: OverviewWorkspaceSummary.ConfigurationSummary {
        .init(value: scenes.value, unit: scenes.unit, rows: scenes.rows,
              status: scenes.status + " · " + (automation.enabled ? (automation.paused ? "Automation paused" : "Automation on") : "Automation off"))
    }
    private func refreshConfiguration() async {
        lastConfigurationRead = Date()
        let revision = profiles.activeProfileRevision
        do {
            let snapshot = try await PolicyGroupService.load()
            guard !Task.isCancelled, revision == profiles.activeProfileRevision else { return }
            let rules = RuleDraftDocument(snapshot.localRules).rules.compactMap { $0.rule.flatMap(RuleForm.init) }
                .filter { $0.type == "PROCESS-PATH" || $0.type == "PROCESS-NAME" }
            applications = .init(value: String(rules.count), unit: "local rules",
                rows: rules.prefix(3).map { ($0.payload as NSString).lastPathComponent + " → " + $0.target },
                status: rules.isEmpty ? "Uses subscription rules" : "First \(min(3, rules.count)) rules · Saved configuration")
            let grouped = Dictionary(grouping: snapshot.effective, by: \.type)
            policies = .init(value: String(snapshot.effective.count), unit: "groups",
                rows: grouped.keys.sorted().map { "\($0) · \(grouped[$0]?.count ?? 0)" }, status: "Saved configuration")
        } catch {
            guard !Task.isCancelled, revision == profiles.activeProfileRevision else { return }
            applications = .init(value: "—", unit: "rules", rows: [], status: "Configuration unavailable")
            policies = .init(value: "—", unit: "groups", rows: [], status: "Configuration unavailable")
        }
        do {
            let saved = try ScenarioService.list().sorted { $0.name < $1.name }
            scenes = .init(value: String(saved.count), unit: "saved", rows: Array(saved.prefix(3).map(\.name)), status: saved.count > 3 ? "First 3 scenes · Current subscription" : "Current subscription")
        } catch { scenes = .init(value: "—", unit: "saved", rows: [], status: "Unavailable") }
    }
    private func refresh() async {
        guard PolicyGroupService.canReadRuntime else {
            rows = []; connectionCount = nil; processCount = nil; activityStatus = "Activity is available when the core is ready"; return
        }
        let generation = ClashController.shared.runtimeGeneration
        do {
            let raw = try await ApplicationRoutingService.connections()
            let connections = await ConnectionProcessResolver.shared.resolve(raw)
            guard !Task.isCancelled, generation == ClashController.shared.runtimeGeneration, PolicyGroupService.canReadRuntime else { return }
            let visible = connections.filter { !$0.identity.isAres }
            let groups = Dictionary(grouping: visible, by: { $0.identity.key })
            var allRows: [OverviewWorkspaceSummary.ProcessRow] = []
            for (key, members) in groups {
                allRows.append(.init(id: key, name: members.first?.identity.name ?? "Unknown", connections: members.count))
            }
            allRows.sort { lhs, rhs in
                if lhs.connections == rhs.connections { return lhs.name < rhs.name }
                return lhs.connections > rhs.connections
            }
            connectionCount = visible.count; processCount = groups.count; rows = allRows
            activityStatus = visible.isEmpty ? "No active connections" : "All sources · Ares excluded"
        } catch {
            guard !Task.isCancelled, generation == controller.runtimeGeneration else { return }
            rows = []; connectionCount = nil; processCount = nil; activityStatus = "Activity could not be read"
        }
    }
}
