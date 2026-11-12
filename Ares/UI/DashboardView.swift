import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var clashViewModel: ClashViewModel
    @EnvironmentObject var clashController: ClashController
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            StatusBanner().padding(.horizontal, 28)
            DashboardComposition(
                runtime: clashViewModel.runtimeState.title,
                version: clashViewModel.coreVersionInfo.displayVersion,
                status: runtimeStatus,
                api: "HTTP :\(appState.tunEnabled ? ClashPorts.tunMixed : ClashPorts.defaultMixed) · SOCKS :\(appState.tunEnabled ? ClashPorts.tunSocks : ClashPorts.defaultSocks) · API :\(clashController.currentPort)"
            ) {
                TrafficCard()
            } controls: {
                ControlCenterCard()
            } details: {
                CurrentProxyCard()
                ExitIdentityCard()
                ConnectivityCard()
            } advanced: {
                SubscriptionCard()
                DNSConfigCard()
                BypassSettingsCard()
                MITMConfigCard()
                ClashInfoCard()
                SystemInfoCard()
            }
        }
        .navigationTitle("Dashboard")
    }

    private var runtimeStatus: DSStatus {
        switch clashViewModel.runtimeState {
        case .running, .apiReady: return .good
        case .launching, .processRunning, .stopping: return .warning
        case .failed: return .critical
        case .stopped: return .idle
        }
    }
}

// MARK: - Status banner

private struct StatusBanner: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        if let operation = appState.operationStatus {
            banner(
                icon: "arrow.triangle.2.circlepath",
                text: operation.title,
                tint: .statusWarn,
                showsSpinner: true
            )
        } else if let error = appState.lastOperationError {
            banner(icon: "exclamationmark.triangle.fill", text: error, tint: .statusBad, showsSpinner: false)
        }
    }

    private func banner(icon: String, text: String, tint: Color, showsSpinner: Bool) -> some View {
        HStack(spacing: DS.Space.sm) {
            if showsSpinner {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: icon)
                    .font(DS.Typography.metadata.weight(.semibold))
            }
            Text(text)
                .font(DS.Typography.secondary.weight(.medium))
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, DS.Space.md)
        .padding(.vertical, DS.Space.sm)
        .background(RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous).fill(tint.opacity(0.1)))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous)
                .strokeBorder(tint.opacity(0.18), lineWidth: DS.hairline)
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
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
            points: model.dataPoints.enumerated().map { index, point in
                OverviewTrafficPoint(id: index, time: point.time, download: Double(point.download), upload: Double(point.upload))
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
