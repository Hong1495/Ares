import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var clashViewModel: ClashViewModel
    @EnvironmentObject var clashController: ClashController
    @EnvironmentObject var appState: AppState


    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                // Row 1: Proxy Service, Advanced mode, Proxy Mode
                Row1Grid()

                // Row 2: Current Proxy, IP Address, Connectivity
                Row2Grid()

                // Row 3: Network Traffic (Graph)
                EnhancedTrafficGraphView()

                // Row 4: Subscription, DNS, Bypass Rules
                Row4Grid()

                // Row 5: MITM Config, Clash Core, System
                Row5Grid()
            }
            .padding()
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Overview")
    }
}

// Row 1: Proxy Service, Advanced mode, Proxy Mode
private struct Row1Grid: View {
    private var columns: [GridItem] {
        [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
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
        [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
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
        [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
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
        [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
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


struct ProxyServiceCard: View {
    @EnvironmentObject var clashViewModel: ClashViewModel
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
                Label {
                    Text("Proxy Service")
                } icon: {
                    Image(systemName: "bolt.horizontal")
                        .fontWeight(.light)
                        .frame(width: 20)
                }
                .font(.headline.weight(.medium))
                .frame(height: 24) // Align Header

            Divider()

            Spacer()

            // Combined Clash + System Proxy Toggle
            HStack {
                Text("Enable Proxy")
                    .font(.body)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { clashViewModel.isRunning && appState.systemProxyEnabled },
                    set: { enabled in
                        Task {
                            if enabled {
                                // Start Clash first
                                await clashViewModel.start()
                                // Wait a bit for Clash to be ready
                                try? await Task.sleep(nanoseconds: 500_000_000)
                                // Then enable system proxy
                                await appState.toggleSystemProxy()
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

            let statusText = clashViewModel.isRunning ?
                (appState.systemProxyEnabled ? "Proxy enabled (port 7890)" : "Clash running (Proxy OFF)") :
                "Proxy disabled"

            Text(statusText)
                .font(.footnote)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            // Spacer() removed for bottom alignment
        }
        .padding()
        .frame(height: 150)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }
}


struct ProxyModeCard: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text("Proxy Mode")
            } icon: {
                Image(systemName: "arrow.triangle.branch")
                    .fontWeight(.light)
                    .frame(width: 20)
            }
            .font(.headline.weight(.medium))
            .frame(height: 24) // Align Header

            Divider()

            Spacer()

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

            // Spacer() removed for bottom alignment
            // Removed mode description to save space/align
        }
        .padding()
        .frame(height: 150)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }

    private func modeIcon(_ mode: ClashConfig.Mode) -> String {
        switch mode {
        case .rule: return "list.bullet.indent"
        case .global: return "map"
        case .direct: return "arrow.turn.up.right"
        }
    }
}



