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
                ConnectivityCard()
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
    @State private var rows: [OverviewWorkspaceSummary.ProcessRow] = []
    @State private var connectionCount: Int?
    @State private var processCount: Int?
    @State private var activityStatus = "Waiting for activity"
    @Environment(\.scenePhase) private var phase

    var body: some View {
        let summary = NetworkQuality.Summary(quality.window.samples["gstatic"] ?? [])
        OverviewWorkspaceSummary(processes: rows, activityStatus: activityStatus,
            connections: connectionCount, processCount: processCount,
            qualityStatus: quality.enabled ? quality.status : "Monitoring is off · Open Network Quality to start",
            qualityGroup: quality.group.isEmpty ? "No monitored policy" : quality.group,
            qualityValue: quality.enabled ? summary.successPercent.map { String(format: "%.1f%%", $0) } ?? "—" : "—",
            qualityDetail: "Google probe success",
            route: quality.enabled ? quality.window.route?.path.joined(separator: " → ") ?? "Waiting for measured results" : "Periodic HTTPS and DNS measurements",
            openActivity: { appState.selection = .connections },
            openApplications: { appState.selection = .applications },
            openQuality: { appState.selection = .quality },
            openPolicies: { appState.selection = .policies },
            openScenes: { appState.selection = .scenes })
        .task(id: phase) {
            guard phase == .active else { return }
            while !Task.isCancelled {
                await refresh()
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
            }
        }
        .onChange(of: controller.runtimeGeneration) { _, _ in
            rows = []; connectionCount = nil; processCount = nil
            activityStatus = "Waiting for current runtime"
        }
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
            connectionCount = visible.count; processCount = groups.count; rows = Array(allRows.prefix(3))
            activityStatus = visible.isEmpty ? "No active connections" : "Top \(rows.count) sources by connections · Ares excluded"
        } catch {
            guard !Task.isCancelled else { return }
            rows = []; connectionCount = nil; processCount = nil; activityStatus = "Activity could not be read"
        }
    }
}
