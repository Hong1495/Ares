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
                
                // Subscription & Connectivity Row
                HStack(alignment: .top, spacing: 16) {
                    SubscriptionCard()
                    ConnectivityTestView()
                }
                
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
            MITMModeCard()
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
            Label {
                Text(clashViewModel.isRunning ? "Clash Running" : "Clash Stopped")
            } icon: {
                Image(systemName: clashViewModel.isRunning ? "bolt.horizontal" : "bolt.horizontal")
                    .fontWeight(.light)
                    .frame(width: 16)
            }
            .font(.footnote.weight(.medium))
                .foregroundStyle(clashViewModel.isRunning ? .green : .secondary)
            Spacer()
            Label {
                Text("Port: 7890")
            } icon: {
                Image(systemName: "link")
                    .fontWeight(.light)
                    .frame(width: 16)
            }
            .font(.footnote.weight(.medium))
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
            .disabled(clashViewModel.isToggling)
            
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

// TUN Mode Card
struct TUNModeCard: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var clashViewModel: ClashViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
                Label {
                    Text("TUN Mode")
                } icon: {
                    Image(systemName: "bolt.shield")
                        .fontWeight(.light)
                        .frame(width: 20)
                }
                .font(.headline.weight(.medium))
                .frame(height: 24) // Align Header
            
            Divider()
            
            Spacer()
            
            Toggle("Enable TUN", isOn: Binding(
                get: { appState.tunEnabled },
                set: { _ in
                    appState.toggleTUN()
                }
            ))
            .toggleStyle(SwitchToggleStyle(tint: .blue))
            .disabled(clashViewModel.isToggling)
            
            Text(appState.tunEnabled ? "TUN Mode is Active" : "TUN Mode is Inactive")
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



// MITM Mode Card
struct MITMModeCard: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text("MITM Mode")
            } icon: {
                // "Simple line icon" replacement: eyeglasses (implies inspection/viewing)
                Image(systemName: "eyeglasses")
                    .fontWeight(.light)
                    .frame(width: 20)
            }
            .font(.headline.weight(.medium))
            .frame(height: 24) // Align Header
            
            Divider()
            
            Spacer()
            
            Toggle("Enable MITM", isOn: Binding(
                get: { appState.mitmEnabled },
                set: { _ in
                    appState.toggleMITM()
                }
            ))
            .toggleStyle(SwitchToggleStyle(tint: .purple))
            
            HStack {
                // Port Display
                let portText = appState.mitmEnabled ? "Active (Port \(NetworkMITMService.shared.currentPort))" : "Inactive"
                Text("MITM \(portText)")
                    .font(.footnote)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Button(action: {
                    Task {
                        do {
                            try await CertificateManager.shared.installToKeychain()
                            // Show success with instructions
                            await MainActor.run {
                                let alert = NSAlert()
                                alert.messageText = "Certificate Added to Keychain"
                                alert.informativeText = """
                                The Ares MITM certificate has been added to your keychain.
                                
                                ⚠️ Important: You must now trust it manually:
                                
                                1. Open "Keychain Access" app (press OK to open)
                                2. Find "Ares MITM Proxy CA" in your login keychain
                                3. Double-click the certificate
                                4. Expand "Trust" section
                                5. Set "When using this certificate" to "Always Trust"
                                6. Close the window and enter your password
                                """
                                alert.alertStyle = .informational
                                alert.addButton(withTitle: "Open Keychain Access")
                                alert.addButton(withTitle: "OK")
                                
                                let response = alert.runModal()
                                if response == .alertFirstButtonReturn {
                                    // Open Keychain Access
                                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Keychain Access.app"))
                                }
                            }
                        } catch {
                            // Show error alert
                            await MainActor.run {
                                let alert = NSAlert()
                                alert.messageText = "Installation Failed"
                                alert.informativeText = "Failed to install CA certificate: \(error.localizedDescription)"
                                alert.alertStyle = .warning
                                alert.addButton(withTitle: "OK")
                                alert.runModal()
                            }
                        }
                    }
                }) {
                    Text("Install CA")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("Export Root CA to Downloads for installation")
            }
            
            // Spacer() removed for bottom alignment
        }
        .padding()
        .frame(height: 150)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }
}
