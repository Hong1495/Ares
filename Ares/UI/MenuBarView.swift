import SwiftUI
import AppKit

struct MenuBarView: View {
    @ObservedObject var appState = AppState.shared
    @ObservedObject var clashViewModel = ClashViewModel.shared
    @ObservedObject var clashController = ClashController.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider().opacity(0.6)

            traffic

            Divider().opacity(0.6)

            toggles

            Divider().opacity(0.6)

            modeSelector

            Divider().opacity(0.6)

            footer
        }
        .frame(width: 288)
        .background(DS.canvas)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: DS.Space.sm) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(headline)
                    .font(DS.Typography.body.weight(.semibold))
                    .lineLimit(1)
                Text(subheadline)
                    .font(DS.Typography.metadata)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: DS.Space.xs)

            if let ms = clashController.primaryLatency {
                HStack(alignment: .lastTextBaseline, spacing: 1) {
                    Text("\(ms)")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("ms")
                        .font(DS.Typography.caption)
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(Color.latency(ms))
            } else {
                Text("-- ms")
                    .font(DS.Typography.secondary.monospaced().weight(.medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, DS.Space.md)
        .padding(.vertical, DS.Space.md)
    }

    // MARK: - Traffic

    private var traffic: some View {
        HStack(spacing: DS.Space.lg) {
            speed(icon: "arrow.down", value: clashController.traffic.down, color: .seriesDown)
            speed(icon: "arrow.up", value: clashController.traffic.up, color: .seriesUp)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Space.md)
        .padding(.vertical, DS.Space.sm)
    }

    private func speed(icon: String, value: Int64, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(DS.Typography.caption.weight(.semibold))
                .foregroundStyle(color)
            Text(Self.formatSpeed(value))
                .font(DS.Typography.metadata.monospaced().weight(.medium))
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Toggles

    private var toggles: some View {
        VStack(spacing: DS.Space.sm) {
            DSToggleRow(
                icon: "globe",
                title: "System Proxy",
                subtitle: appState.systemProxyEnabled ? "Routing system traffic" : "Off",
                tint: .statusGood,
                isOn: Binding(
                    get: { appState.systemProxyEnabled },
                    set: { _ in Task { await toggleSystemProxy() } }
                )
            )

            DSToggleRow(
                icon: "bolt.shield",
                title: "TUN Mode",
                subtitle: appState.tunEnabled ? "Layer-3 capture" : "Off",
                tint: .seriesDown,
                isOn: Binding(
                    get: { appState.tunEnabled },
                    set: { _ in appState.toggleTUN() }
                )
            )

            DSToggleRow(
                icon: "eye",
                title: "MITM",
                subtitle: appState.mitmEnabled ? "Intercepting" : "Off",
                tint: .seriesUp,
                isOn: Binding(
                    get: { appState.mitmEnabled },
                    set: { _ in appState.toggleMITM() }
                )
            )
        }
        .padding(.horizontal, DS.Space.md)
        .padding(.vertical, DS.Space.md)
        .disabled(appState.isPerformingNetworkOperation)
    }

    // MARK: - Mode

    private var modeSelector: some View {
        HStack(spacing: 3) {
            ForEach([ClashConfig.Mode.rule, .global, .direct], id: \.self) { mode in
                Button {
                    Task { await appState.setMode(mode) }
                } label: {
                    Text(mode.displayLabel.replacingOccurrences(of: " mode", with: ""))
                        .font(DS.Typography.metadata.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .foregroundStyle(appState.currentMode == mode ? Color.primary : Color.secondary)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(appState.currentMode == mode
                                      ? DS.surface
                                      : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(
                                    appState.currentMode == mode
                                        ? Color(nsColor: .separatorColor)
                                        : Color.clear,
                                    lineWidth: DS.hairline
                                )
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .padding(.horizontal, DS.Space.md)
        .padding(.vertical, DS.Space.sm)
        .disabled(appState.isPerformingNetworkOperation)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: DS.Space.xs) {
            MenuActionButton(icon: "point.3.connected.trianglepath.dotted", title: "Activity") {
                WindowAccessor.showMainWindow(selection: .connections, openWindow: openWindow)
            }

            MenuActionButton(icon: "slider.horizontal.3", title: "Proxies") {
                WindowAccessor.showMainWindow(selection: .proxies, openWindow: openWindow)
            }

            MenuActionButton(icon: "gearshape", title: "Settings") {
                WindowAccessor.showMainWindow(selection: .settings, openWindow: openWindow)
            }

            Spacer(minLength: 0)

            Button {
                AppTerminationCoordinator.shared.requestQuit()
            } label: {
                Image(systemName: "power")
                    .font(DS.Typography.metadata.weight(.semibold))
                    .foregroundStyle(Color.statusBad)
                    .frame(width: 26, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.statusBad.opacity(0.1))
                    )
            }
            .buttonStyle(.plain)
            .help("Quit Ares")
        }
        .padding(.horizontal, DS.Space.md)
        .padding(.vertical, DS.Space.sm)
    }

    // MARK: - Derived

    private var headline: String {
        if appState.systemProxyEnabled && clashViewModel.isRunning { return "Protected" }
        if appState.tunEnabled && clashViewModel.isRunning { return "TUN active" }
        return clashViewModel.runtimeState.title
    }

    private var subheadline: String {
        if case .failed = clashViewModel.runtimeState { return "Core failed to start" }
        return appState.currentMode.displayLabel
    }

    private var statusColor: Color {
        switch clashViewModel.runtimeState {
        case .running, .apiReady: return .statusGood
        case .launching, .processRunning, .stopping: return .statusWarn
        case .failed: return .statusBad
        case .stopped: return .statusIdle
        }
    }

    private func toggleSystemProxy() async {
        await appState.toggleSystemProxy()
    }

    private static func formatSpeed(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0 B/s" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes) + "/s"
    }
}

struct MenuActionButton: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(DS.Typography.caption.weight(.medium))
                Text(title)
                    .font(DS.Typography.metadata.weight(.medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
