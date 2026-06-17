import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var clashViewModel: ClashViewModel
    @EnvironmentObject var clashController: ClashController
    @EnvironmentObject var appState: AppState
    @State private var showAdvancedDashboard = false


    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                RuntimeOverviewCard()

                // Row 1: Proxy Service, Advanced mode, Proxy Mode
                Row1Grid()

                // Row 2: Current Proxy, IP Address, Connectivity
                Row2Grid()

                // Row 3: Network Traffic (Graph)
                EnhancedTrafficGraphView()

                DisclosureGroup(isExpanded: $showAdvancedDashboard) {
                    VStack(spacing: 16) {
                        // Row 4: Subscription, DNS, Bypass Rules
                        Row4Grid()

                        // Row 5: MITM Config, Clash Core, System
                        Row5Grid()
                    }
                    .padding(.top, 12)
                } label: {
                    HStack {
                        Label("Advanced Diagnostics", systemImage: "slider.horizontal.3")
                            .font(.headline.weight(.medium))
                        Spacer()
                        Text(showAdvancedDashboard ? "Hide" : "Show")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(16)
                .cardStyle()
            }
            .padding()
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Dashboard")
    }
}

private enum DashboardGrid {
    static let columns = [
        GridItem(.adaptive(minimum: 260, maximum: 420), spacing: 16)
    ]
}

// Row 1: Proxy Service, Advanced mode, Proxy Mode
private struct Row1Grid: View {
    private var columns: [GridItem] {
        DashboardGrid.columns
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ProxyServiceCard()
            AdvancedModeCard()
            ProxyModeCard()
        }
    }
}

// Row 2: Current Proxy, IP Address, Connectivity
private struct Row2Grid: View {
    private var columns: [GridItem] {
        DashboardGrid.columns
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            CurrentProxyCard()
            IpAddressCard()
            ConnectivityTestView()
        }
    }
}

// Row 4: Subscription, DNS, Bypass Rules
private struct Row4Grid: View {
    private var columns: [GridItem] {
        DashboardGrid.columns
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            SubscriptionCard()
            DNSConfigCard()
            BypassSettingsCard()
        }
    }
}

// Row 5: MITM Config, Clash Core, System
private struct Row5Grid: View {
    private var columns: [GridItem] {
        DashboardGrid.columns
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            MITMConfigCard()
            ClashInfoCard()
            SystemInfoCard()
        }
    }
}


// MARK: - Subviews

// MARK: - Subviews


struct RuntimeOverviewCard: View {
    @EnvironmentObject var clashViewModel: ClashViewModel
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var clashController: ClashController

    private let columns = [
        GridItem(.adaptive(minimum: 180), spacing: 12)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            statusBlock(
                title: "Core",
                value: clashViewModel.runtimeState.title,
                detail: coreDetail,
                icon: "cpu",
                color: runtimeColor
            )

            statusBlock(
                title: "System Proxy",
                value: appState.systemProxyEnabled ? "Enabled" : "Off",
                detail: proxyDetail,
                icon: "network",
                color: appState.systemProxyEnabled ? .green : .secondary
            )

            statusBlock(
                title: "TUN",
                value: appState.tunEnabled ? "Enabled" : "Off",
                detail: "API :\(clashController.currentPort)",
                icon: "point.3.connected.trianglepath.dotted",
                color: appState.tunEnabled ? .blue : .secondary
            )

            statusBlock(
                title: "Exit IP",
                value: appState.publicIP,
                detail: appState.countryCode ?? "Unknown",
                icon: "location",
                color: .orange
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var runtimeColor: Color {
        switch clashViewModel.runtimeState {
        case .running, .apiReady: return .green
        case .launching, .processRunning, .stopping: return .orange
        case .failed: return .red
        case .stopped: return .secondary
        }
    }

    private var coreDetail: String {
        if clashViewModel.isCoreUpdateAvailable, let latest = clashViewModel.latestCoreRelease {
            return "\(clashViewModel.coreVersionInfo.displayVersion) -> \(latest.version)"
        }
        return clashViewModel.coreVersionInfo.displayVersion
    }

    private var proxyDetail: String {
        let httpPort = appState.tunEnabled ? ClashPorts.tunMixed : ClashPorts.defaultMixed
        let socksPort = appState.tunEnabled ? ClashPorts.tunSocks : ClashPorts.defaultSocks
        return appState.systemProxyEnabled ? "HTTP :\(httpPort), SOCKS :\(socksPort)" : "No system routing"
    }

    private func statusBlock(title: String, value: String, detail: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ProxyServiceCard: View {
    @EnvironmentObject var clashViewModel: ClashViewModel
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // 1. Header Zone
            HStack(spacing: 12) {
                Image(systemName: "globe")
                    .font(.system(size: 18, weight: .light))
                    .frame(width: 24, height: 24, alignment: .center)
                    .foregroundStyle(.primary)

                Text("Proxy Service")
                    .font(.headline.weight(.medium))

                Spacer()
            }
            .frame(height: 24)
            .padding(16)

            Divider()
                .padding(.horizontal, 16)

            // 2. Content Zone
            VStack(alignment: .leading, spacing: 12) {
                 // Combined Clash + System Proxy Toggle
                HStack {
                    Text("System Proxy")
                        .font(.body)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { clashViewModel.runtimeState.isAPIReady && appState.systemProxyEnabled },
                        set: { enabled in
                            Task {
                                if enabled {
                                    // Start Clash first
                                    await clashViewModel.start()
                                    // Then enable system proxy
                                    if clashViewModel.runtimeState.isAPIReady {
                                        await appState.toggleSystemProxy()
                                    }
                                } else {
                                    // Disable system proxy first
                                    if appState.systemProxyEnabled {
                                        await appState.toggleSystemProxy()
                                    }
                                    // Then stop Clash
                                    await clashViewModel.stop()
                                }
                            }
                        }
                    ))
                    .toggleStyle(SwitchToggleStyle(tint: .green))
                    .labelsHidden()
                    .disabled(clashViewModel.isToggling)
                }

                let statusText = clashViewModel.runtimeState.isActive ?
                    (appState.systemProxyEnabled ? "Proxy enabled" : "\(clashViewModel.runtimeState.title) (Proxy OFF)") :
                    "Proxy disabled"

                Text(statusText)
                    .font(.footnote)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(height: 150)
        .cardStyle()
    }
}


struct ProxyModeCard: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // 1. Header Zone
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 18, weight: .light))
                    .frame(width: 24, height: 24, alignment: .center)
                    .foregroundStyle(.primary)

                Text("Proxy Mode")
                    .font(.headline.weight(.medium))

                Spacer()
            }
            .frame(height: 24)
            .padding(16)

            Divider()
                .padding(.horizontal, 16)

            // 2. Content Zone
            HStack(spacing: 12) {
                ForEach([ClashConfig.Mode.rule, .global, .direct], id: \.self) { mode in
                    Button {
                        Task {
                            await appState.setMode(mode)
                        }
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: modeIcon(mode))
                                .font(.title2)
                            Text(mode.rawValue.capitalized)
                                .font(.footnote)
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            appState.currentMode == mode ?
                            LinearGradient(colors: [Color.blue, Color.blue.opacity(0.8)], startPoint: .top, endPoint: .bottom) :
                            LinearGradient(colors: [Color.gray.opacity(0.1), Color.gray.opacity(0.05)], startPoint: .top, endPoint: .bottom)
                        )
                        .foregroundStyle(appState.currentMode == mode ? .white : .primary)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(appState.currentMode == mode ? Color.blue : Color.clear, lineWidth: 2)
                        )
                        .shadow(color: appState.currentMode == mode ? Color.blue.opacity(0.3) : Color.clear, radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 150)
        .cardStyle()
    }

    private func modeIcon(_ mode: ClashConfig.Mode) -> String {
        switch mode {
        case .rule: return "list.bullet.indent"
        case .global: return "map"
        case .direct: return "arrow.turn.up.right"
        }
    }
}
