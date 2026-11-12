import SwiftUI
import AppKit

struct MenuBarView: View {
    @ObservedObject var appState = AppState.shared
    @ObservedObject var clashViewModel = ClashViewModel.shared
    @ObservedObject var clashController = ClashController.shared
    @AppStorage(DefaultsKeys.ipReputationEnabled) private var reputationEnabled = false
    @ObservedObject private var reputation = IPReputationService.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        MenuBarPanel(
            country: appState.countryCode,
            ip: appState.publicIP,
            latency: clashViewModel.isRunning && appState.currentMode != .direct ? clashController.primaryLatency : nil,
            showsRisk: reputationEnabled,
            risk: reputation.result?.ip == appState.publicIP ? reputation.result?.risk : nil,
            download: Self.formatSpeed(clashViewModel.isRunning ? clashController.traffic.down : 0),
            upload: Self.formatSpeed(clashViewModel.isRunning ? clashController.traffic.up : 0),
            openDashboard: { WindowAccessor.showMainWindow(selection: .dashboard, openWindow: openWindow) },
            openActivity: { WindowAccessor.showMainWindow(selection: .connections, openWindow: openWindow) },
            openSettings: { WindowAccessor.showMainWindow(selection: .settings, openWindow: openWindow) },
            quit: { AppTerminationCoordinator.shared.requestQuit() }
        )
    }

    private static func formatSpeed(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0 B/s" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) + "/s"
    }
}
