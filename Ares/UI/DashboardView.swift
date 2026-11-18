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
    @ObservedObject private var history = ClashController.shared.trafficHistory

    var body: some View {
        OverviewTrafficCard(
            points: history.snapshot.points.map { point in
                OverviewTrafficPoint(time: point.time, download: Double(point.download), upload: Double(point.upload), segment: point.segment)
            },
            download: Self.formatSpeed(history.snapshot.currentDownload),
            upload: Self.formatSpeed(history.snapshot.currentUpload)
        )
    }

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
    @State private var saved = OverviewConfiguration()
    @State private var deviceConnections: [String: Int]?
    @State private var lastConfigurationRead = Date.distantPast
    @State private var rows: [OverviewWorkspaceSummary.ProcessRow] = []
    @State private var connectionCount: Int?
    @State private var processCount: Int?
    @State private var activityStatus = "Waiting for activity"
    @Environment(\.scenePhase) private var phase

    var body: some View {
        OverviewWorkspaceSummary(probes: probes, configuration: configuration, openResources: { appState.selection = .resources }, openDevices: { appState.selection = .devices }, processes: rows, activityStatus: activityStatus,
            connections: connectionCount, processCount: processCount,
            qualityStatus: quality.enabled ? quality.status : "Monitoring is off · Open Quality to start",
            qualityGroup: quality.group.isEmpty ? "No monitored policy" : quality.group,
            route: quality.enabled ? quality.window.route?.path.joined(separator: " → ") ?? "Waiting for measured results" : "Periodic HTTPS and DNS measurements",
            openActivity: { appState.selection = .connections },
            openApplications: { appState.selection = .applications },
            openQuality: { appState.selection = .quality },
            openPolicies: { appState.selection = .policies },
            openScenes: { appState.selection = .scenes })
        .task(id: "\(phase)-\(profiles.activeProfileRevision)") {
            guard phase == .active else { return }
            saved = OverviewConfiguration()
            deviceConnections = nil
            lastConfigurationRead = .distantPast
            while !Task.isCancelled {
                if Date().timeIntervalSince(lastConfigurationRead) >= 30 { await refreshConfiguration() }
                await refresh()
                refreshDevices()
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
            }
        }
        .onChange(of: controller.runtimeGeneration) { _, _ in
            rows = []; connectionCount = nil; processCount = nil
            activityStatus = "Waiting for current runtime"
            deviceConnections = nil; refreshDevices()
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
    private var automationState: OverviewConfiguration.Automation {
        automation.enabled ? (automation.paused ? .paused : .on) : .off
    }
    private var configuration: OverviewConfiguration {
        var configuration = saved
        if let names = saved.scenes?.names {
            configuration.scenes = .init(names: names, automation: automationState)
        }
        return configuration
    }
    private func refreshConfiguration() async {
        lastConfigurationRead = Date()
        let revision = profiles.activeProfileRevision
        do {
            let snapshot = try await PolicyGroupService.load()
            guard !Task.isCancelled, revision == profiles.activeProfileRevision else { return }
            let rules = RuleDraftDocument(snapshot.localRules).rules.compactMap { $0.rule.flatMap(RuleForm.init) }
                .filter { $0.type == "PROCESS-PATH" || $0.type == "PROCESS-NAME" }
            saved.applications = rules.map { .init(application: ($0.payload as NSString).lastPathComponent, target: $0.target) }
            saved.policies = Dictionary(grouping: snapshot.effective, by: \.type).mapValues(\.count)
        } catch {
            guard !Task.isCancelled, revision == profiles.activeProfileRevision else { return }
            saved.applications = nil
            saved.policies = nil
        }
        do {
            let managed = try await ManagedWorkspaceService.load()
            guard !Task.isCancelled, revision == profiles.activeProfileRevision else { return }
            let entries = try ManagedResources.entries(source: managed.source, draft: managed.document.resources)
            let nodes = entries.filter { !$0.provider }.count
            let providers = entries.filter(\.provider).count
            let local = entries.filter(\.local).count
            saved.resources = .init(nodes: nodes, providers: providers, local: local)
        } catch {
            guard !Task.isCancelled, revision == profiles.activeProfileRevision else { return }
            saved.resources = nil
        }
        do {
            let saved = try ScenarioService.list().sorted { $0.name < $1.name }
            self.saved.scenes = .init(names: saved.map(\.name), automation: automationState)
        } catch { saved.scenes = nil }
    }
    private func refreshDevices() {
        do {
            let saved = try ManagedWorkspaceService.read(profiles.activeProfileID).devices
            let enabled = saved.filter(\.enabled)
            let names = Set(enabled.map(\.listenerName))
            let live = deviceConnections.map { counts in
                let matched = counts.filter { names.contains($0.key) && $0.value > 0 }
                return OverviewConfiguration.Devices.Live(active: matched.count, connections: matched.values.reduce(0, +))
            }
            self.saved.devices = .init(enabled: enabled.count, disabled: saved.count - enabled.count, live: live)
        } catch { saved.devices = nil }
    }
    private func refresh() async {
        guard PolicyGroupService.canReadRuntime else {
            deviceConnections = nil; rows = []; connectionCount = nil; processCount = nil; activityStatus = "Activity is available when the core is ready"; return
        }
        let generation = ClashController.shared.runtimeGeneration
        do {
            let raw = try await ApplicationRoutingService.connections()
            let connections = await ConnectionProcessResolver.shared.resolve(raw)
            guard !Task.isCancelled, generation == ClashController.shared.runtimeGeneration, PolicyGroupService.canReadRuntime else { return }
            deviceConnections = Dictionary(grouping: raw.filter { !($0.metadata.inboundName ?? "").isEmpty }, by: { $0.metadata.inboundName! }).mapValues(\.count)
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
            deviceConnections = nil; rows = []; connectionCount = nil; processCount = nil; activityStatus = "Activity could not be read"
        }
    }
}
