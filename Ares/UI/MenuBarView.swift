import SwiftUI

struct MenuBarView: View {
    @ObservedObject var appState = AppState.shared
    @ObservedObject var clashViewModel = ClashViewModel.shared
    @EnvironmentObject var clashController: ClashController

    var body: some View {
        VStack(spacing: 0) {
            // Header: Status & Quick Actions
            HStack {
                Circle()
                    .fill(clashViewModel.isRunning ? Color.green : Color.red)
                    .frame(width: 8, height: 8)

                Text(clashViewModel.isRunning ? "Ares Running" : "Stopped")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                Button(action: {
                    NSApp.activate(ignoringOtherApps: true)
                    // Open main window logic handled by AppDelegate usually
                    if let window = NSApp.windows.first {
                        window.makeKeyAndOrderFront(nil)
                    }
                }) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .help("Open Dashboard")

                Button(action: {
                    NSApp.terminate(nil)
                }) {
                    Image(systemName: "power")
                        .font(.system(size: 14))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Quit Ares")
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Speed Graph (Mini)
            // We can reuse a simplified graph or just show large stats
            HStack(spacing: 20) {
                SpeedStat(icon: "arrow.down", value: formatSpeed(clashController.traffic.down), label: "Download")
                Divider().frame(height: 30)
                SpeedStat(icon: "arrow.up", value: formatSpeed(clashController.traffic.up), label: "Upload")
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Quick Toggles
            VStack(spacing: 4) {
                ToggleRow(
                    title: "System Proxy",
                    icon: "globe",
                    tint: .green,
                    isOn: Binding(
                        get: { appState.systemProxyEnabled },
                        set: { _ in Task { await appState.toggleSystemProxy() } }
                    )
                )

                ToggleRow(
                    title: "Enhanced Mode (TUN)",
                    icon: "bolt.shield",
                    tint: .blue,
                    isOn: Binding(
                        get: { appState.tunEnabled },
                        set: { _ in appState.toggleTUN() }
                    )
                )
            }
            .padding()

            Divider()

            // Mode Select
            HStack {
                Text("Mode:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("", selection: $appState.currentMode) {
                    Text("Rule").tag(ClashConfig.Mode.rule)
                    Text("Global").tag(ClashConfig.Mode.global)
                    Text("Direct").tag(ClashConfig.Mode.direct)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: appState.currentMode) { newMode in
                    Task {
                         await appState.setMode(newMode)
                    }
                }
            }
            .padding()
        }
        .frame(width: 280)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func formatSpeed(_ bytes: Int64) -> String {
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) + "/s"
    }
}

struct SpeedStat: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ToggleRow: View {
    let title: String
    let icon: String
    var tint: Color = .blue
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 16)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 13))
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(SwitchToggleStyle(tint: tint))
                .controlSize(.small)
                .labelsHidden()
        }
        .padding(.vertical, 2)
    }
}
