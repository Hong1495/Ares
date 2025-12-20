import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var clashViewModel: ClashViewModel
    @EnvironmentObject var clashController: ClashController
    @EnvironmentObject var appState: AppState
    

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                StatusHeader()
                MainGrid()
                EnhancedTrafficGraphView()
                SmallStatsGrid()
                ConnectivityTestView()
                InfoGrid()
            }
            .padding()
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Overview")
    }
}

private struct MainGrid: View {
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 380), spacing: 16)]
    }
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            NetworkTrafficCard()
            ProxyModeCard()
            TUNModeCard()
            CurrentProxyCard()
        }
    }
}

private struct InfoGrid: View {
    private var columns: [GridItem] {
        [GridItem(.flexible()), GridItem(.flexible())]
    }
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            IpInfoCard()
            ClashInfoCard()
            TestCard()
            SystemInfoCard()
        }
    }
}

// MARK: - Subviews

struct StatusHeader: View {
    @EnvironmentObject var clashController: ClashController
    @EnvironmentObject var clashViewModel: ClashViewModel
    
    var body: some View {
        HStack {
            Label(clashViewModel.isRunning ? "Clash Running" : "Clash Stopped", 
                  systemImage: clashViewModel.isRunning ? "bolt.fill" : "bolt.slash.fill")
                .font(.caption)
                .foregroundStyle(clashViewModel.isRunning ? .green : .secondary)
            Spacer()
            Label("Port: 7890", systemImage: "network")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }
}

struct NetworkTrafficCard: View {
    @EnvironmentObject var clashViewModel: ClashViewModel
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Proxy Service", systemImage: "network")
                    .font(.headline)
                Spacer()
            }
            
            Spacer()
            
            // Combined Clash + System Proxy Toggle
            Toggle("Enable Proxy", isOn: Binding(
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
            .toggleStyle(SwitchToggleStyle(tint: .blue))
            
            let statusText = clashViewModel.isRunning ? 
                (appState.systemProxyEnabled ? "Proxy enabled (port 7890)" : "Clash running (Proxy OFF)") :
                "Proxy disabled"
            
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
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
            Label("Proxy Mode", systemImage: "arrow.triangle.branch")
                .font(.headline)
            
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
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
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
            
            Text(modeDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .padding()
        .frame(height: 150)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private func modeIcon(_ mode: ClashConfig.Mode) -> String {
        switch mode {
        case .rule: return "list.bullet.rectangle"
        case .global: return "globe"
        case .direct: return "arrow.forward"
        }
    }
    
    private var modeDescription: String {
        switch appState.currentMode {
        case .rule: return "Rule: Auto-select based on rules"
        case .global: return "Global: All traffic through proxy"
        case .direct: return "Direct: No proxy, direct connection"
        }
    }
}

// TUN Mode Card
struct TUNModeCard: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Label("TUN Mode", systemImage: "network")
                    .font(.headline)
                Spacer()
            }
            Spacer()
            
            Toggle("Enable TUN", isOn: Binding(
                get: { appState.tunEnabled },
                set: { _ in
                    appState.toggleTUN()
                }
            ))
            .toggleStyle(SwitchToggleStyle(tint: .blue))
            
            Text(appState.tunEnabled ? "TUN Mode is Active" : "TUN Mode is Inactive")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(height: 150)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }
}

struct ModeButton: View {
    let mode: String
    let isSelected: Bool
    
    var body: some View {
        Button(action: {}) {
            Text(mode)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(isSelected ? Color.blue : Color(nsColor: .windowBackgroundColor))
                .foregroundStyle(isSelected ? .white : .primary)
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

struct SmallStatsGrid: View {
    @EnvironmentObject var clashController: ClashController
    
    var body: some View {
        HStack(spacing: 16) {
            SmallTrafficCard(title: "Total Upload", value: clashController.traffic.up, icon: "arrow.up", color: .orange, showRate: false)
            SmallTrafficCard(title: "Total Download", value: clashController.traffic.down, icon: "arrow.down", color: .blue, showRate: false)
        }
    }
}

struct SmallTrafficCard: View {
    let title: String
    let value: Int64
    let icon: String
    let color: Color
    var unit: String? = nil
    var showRate: Bool = true // Default to showing rate (/s)
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
                .padding(8)
                .background(color.opacity(0.1))
                .clipShape(Circle())
            
            VStack(alignment: .leading) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let unit = unit {
                    Text("\(value) \(unit)")
                        .font(.headline)
                } else {
                    Text(formatBytes(value) + (showRate ? "/s" : ""))
                        .font(.headline)
                }
            }
            Spacer()
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }
    
    func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.zeroPadsFractionDigits = true // Ensure 0 is treated standardly
        
        let formatted = formatter.string(fromByteCount: bytes)
        return formatted == "Zero KB" ? "0 KB" : formatted
    }
}
