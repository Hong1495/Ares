import SwiftUI
import AppKit

struct MenuBarView: View {
    @ObservedObject var appState = AppState.shared
    @ObservedObject var clashViewModel = ClashViewModel.shared
    @ObservedObject var clashController = ClashController.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            // 1. Status Section (Compact: Country + Latency)
            HStack(spacing: 8) {
                // Status Indicator
                Circle()
                    .fill(clashViewModel.isRunning ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                    .shadow(color: (clashViewModel.isRunning ? Color.green : Color.red).opacity(0.5), radius: 2)

                if let country = appState.countryCode {
                    Text(country)
                        .font(.system(size: 14, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.1))
                        .cornerRadius(4)
                }

                Spacer()

                // Latency
                if let ms = clashController.primaryLatency {
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text("\(ms)")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                        Text("ms")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(latencyColor(ms))
                } else if clashViewModel.isRunning {
                    Text("-- ms")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.clear)

            Divider().padding(.horizontal, 16)

            // 2. Traffic Section (Simple Text)
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.cyan)
                    Text(formatSpeed(clashController.traffic.up))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                }

                HStack(spacing: 4) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.green)
                    Text(formatSpeed(clashController.traffic.down))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 16)

            Divider().padding(.horizontal, 16)

            // 3. Toggle Section
            VStack(spacing: 12) {
                MenuToggleRow(
                    title: "System Proxy",
                    icon: "globe",
                    color: .green,
                    isOn: Binding(
                        get: { appState.systemProxyEnabled },
                        set: { _ in Task { await appState.toggleSystemProxy() } }
                    )
                )

                MenuToggleRow(
                    title: "TUN Mode",
                    icon: "bolt.shield",
                    color: .blue,
                    isOn: Binding(
                        get: { appState.tunEnabled },
                        set: { _ in appState.toggleTUN() }
                    )
                )

                MenuToggleRow(
                    title: "MITM Shield",
                    icon: "shield.lefthalf.filled",
                    color: .purple,
                    isOn: Binding(
                        get: { appState.mitmEnabled },
                        set: { _ in appState.toggleMITM() }
                    )
                )
            }
            .padding(16)

            Divider().padding(.horizontal, 16)

            // 4. Mode Selection
            HStack {
                ForEach([ClashConfig.Mode.rule, .global, .direct], id: \.self) { mode in
                    Button(action: {
                        Task { await appState.setMode(mode) }
                    }) {
                        Text(mode.rawValue.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(appState.currentMode == mode ? modeColor(mode).opacity(0.2) : Color.clear)
                            .foregroundStyle(appState.currentMode == mode ? modeColor(mode) : .secondary)
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(appState.currentMode == mode ? modeColor(mode).opacity(0.3) : Color.clear, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)

            // 5. Action Section
            HStack(spacing: 12) {
                MenuActionButton(icon: "square.grid.2x2", title: "Dashboard") {
                    openDashboard()
                }

                MenuActionButton(icon: "gearshape", title: "Settings") {
                    openSettings()
                }

                Spacer()

                Button(action: { NSApp.terminate(nil) }) {
                    Image(systemName: "power")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.red)
                        .padding(8)
                        .background(Color.red.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(Color.primary.opacity(0.03))
        }
        .frame(width: 300)
    }

    private func modeColor(_ mode: ClashConfig.Mode) -> Color {
        switch mode {
        case .rule: return .blue
        case .global: return .orange
        case .direct: return .green
        }
    }

    private func latencyColor(_ ms: Int) -> Color {
        if ms < 100 { return .green }
        if ms < 300 { return .yellow }
        return .red
    }

    private func openDashboard() {
        appState.selection = .dashboard
        showMainWindow()
    }

    private func openSettings() {
        appState.selection = .settings
        showMainWindow()
    }

    private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)

        // Find the main window (could be minimized, hidden, or visible)
        let mainWindow = NSApp.windows.first(where: {
            $0.identifier?.rawValue.contains("main") == true
        }) ?? NSApp.windows.first(where: {
            // Fallback: find any content window that isn't the menu bar extra or inspector
            $0.contentView != nil &&
            $0.identifier?.rawValue != "network-inspector" &&
            !($0.className.contains("MenuBarExtra") || $0.className.contains("StatusBar"))
        })

        if let window = mainWindow {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
        } else {
            // Window was fully closed, reopen via SwiftUI
            openWindow(id: "main")
        }
    }

    private func formatSpeed(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        let formatted = formatter.string(fromByteCount: bytes)
        return formatted == "Zero KB" ? "0 KB/s" : formatted + "/s"
    }
}

struct MenuToggleRow: View {
    let title: String
    let icon: String
    let color: Color
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
                .frame(width: 20)

            Text(title)
                .font(.system(size: 13, weight: .medium))

            Spacer()

            Toggle("", isOn: $isOn)
                .toggleStyle(SwitchToggleStyle(tint: color))
                .controlSize(.small)
                .labelsHidden()
        }
    }
}

struct MenuActionButton: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}
