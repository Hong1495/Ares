import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // App started
        Task {
            // Initial health check and sync on launch
            await checkAndRecoverState()
        }
        
        // Handle Silent Start
        let silent = UserDefaults.standard.bool(forKey: "silentStart")
        if silent {
            print("[AppDelegate] 🤫 Silent start enabled - hiding application")
            // Hide the entire application from foreground
            DispatchQueue.main.async {
                NSApp.hide(nil)
            }
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Force cleanup on exit
        print("🛑 App Terminating - Cleaning up...")
        
        // 1. CRITICAL: Disable system proxy FIRST to prevent network outage
        // This must happen BEFORE we kill Clash, otherwise macOS traffic
        // will try to connect to a dead port (127.0.0.1:7890)
        if UserDefaults.standard.bool(forKey: "systemProxyEnabled") {
            print("🔌 Disabling system proxy...")
            SystemProxyManager.shared.disableAllProxiesSync()
            // NOTE: Keep systemProxyEnabled = true so proxy auto-restarts on next launch
            // User's preference is preserved, only runtime state is cleaned up
        }
        
        // 2. Kill Clash process
        // Synchronous cleanup using sudo pkill directly
        // We use a direct Process call to avoid async/Task issues during termination
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        task.arguments = ["-n", "/usr/bin/pkill", "-9", "-f", "clash-meta"]
        try? task.run()
        task.waitUntilExit()
        
        print("✅ Cleanup complete")
    }
    
    private func checkAndRecoverState() async {
        await Task.yield()
        print("🏥 Performing Startup Health Check...")
        
        // 0. Initialize State first (Loads Prefs, Check Privileges)
        await AppState.shared.initialize()
        
        // 1. Start Clash with retry capability (Gated)
        if ClashViewModel.shared.isRunning {
            print("ℹ️ Clash is already running, skipping explicit start")
        } else {
            print("🚀 Starting Clash...")
            await ClashViewModel.shared.start()
        }
        
        // 2. Sync state with Clash immediately
        await AppState.shared.syncWithClash()
        
        // 3. Restore System Proxy state if enabled (NON-BLOCKING)
        // Run proxy setup in background to not delay app startup
        if AppState.shared.systemProxyEnabled {
            print("🔄 Restoring System Proxy state...")
            Task.detached {
                await AppState.shared.enableSystemProxy()
            }
        }
    }
}

@main
struct AresApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    private let clashViewModel = ClashViewModel.shared
    private let profileService = ProfileService.shared
    private let clashController = ClashController.shared
    @StateObject private var appState = AppState.shared
    @StateObject private var themeService = ThemeService.shared
    
    var body: some Scene {
        WindowGroup(id: "main") {
            MainView()
                .environmentObject(clashViewModel)
                .environmentObject(profileService)
                .environmentObject(clashController)
                .environmentObject(appState)
                .environmentObject(themeService)
                .frame(minWidth: 800, minHeight: 600)
                .onAppear {
                    NSWindow.allowsAutomaticWindowTabbing = false
                }
                .preferredColorScheme(themeService.theme == "dark" ? .dark : (themeService.theme == "light" ? .light : nil))
        }
        .commands {
            // Disable "New Window" to enforce single window behavior
            CommandGroup(replacing: .newItem) { }
        }
        .handlesExternalEvents(matching: Set(arrayLiteral: "main"))
        
        WindowGroup(id: "network-inspector", for: String.self) { $requestId in
            if let id = requestId {
                NetworkInspectorView(requestId: id)
                    .environmentObject(appState) // Pass environment objects if needed
            } else {
               Text("No Request Selected")
            }
        }
        
        // Enhanced Menu Bar
        MenuBarExtra {
            AresMenuBarView(appState: appState, clashViewModel: clashViewModel)
        } label: {
            let proxyStatus = appState.systemProxyEnabled ? "1" : "0"
            let tunStatus = appState.tunEnabled ? "1" : "0"
            Image("Ares_Menu_\(proxyStatus)\(tunStatus)")
        }
    }
}

struct AresMenuBarView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var clashViewModel: ClashViewModel
    @Environment(\.openWindow) var openWindow
    
    var body: some View {
        Button(action: {
            NSApp.activate(ignoringOtherApps: true)
            appState.selection = .dashboard
            openWindow(id: "main")
        }) {
            Label {
                Text("Dashboard")
            } icon: {
                Image(systemName: "square.grid.2x2")
                    .imageScale(.medium)
                    .fontWeight(.light)
                    .frame(width: 18)
            }
        }
        .keyboardShortcut("d", modifiers: [.command])

        Divider()

        // System Proxy Toggle
        Toggle(isOn: Binding(
            get: { appState.systemProxyEnabled },
            set: { _ in
                Task {
                    await appState.toggleSystemProxy()
                }
            }
        )) {
            Label {
                Text("System Proxy")
            } icon: {
                Image(systemName: "bolt.horizontal")
                    .imageScale(.medium)
                    .fontWeight(.light)
                    .frame(width: 18)
            }
        }
        .disabled(clashViewModel.isToggling)
        .keyboardShortcut("p", modifiers: [.command, .shift])
        
        // TUN Mode Toggle
        Toggle(isOn: Binding(
            get: { appState.tunEnabled },
            set: { newValue in
                print("[MenuBar] 🔘 TUN toggle clicked: \(appState.tunEnabled) -> \(newValue)")
                appState.toggleTUN()
            }
        )) {
            Label {
                Text("TUN Mode")
            } icon: {
                Image(systemName: "bolt.shield")
                    .imageScale(.medium)
                    .fontWeight(.light)
                    .frame(width: 18)
            }
        }
        .disabled(clashViewModel.isToggling)
        .keyboardShortcut("t", modifiers: [.command, .shift])
        
        Divider()
        
        // Mode Selector
        Menu {
            Toggle(isOn: Binding(
                get: { appState.currentMode == .rule },
                set: { _ in Task { await appState.setMode(.rule) } }
            )) {
                Label {
                    Text("Rule")
                } icon: {
                    Image(systemName: "list.bullet.indent")
                        .imageScale(.medium)
                        .fontWeight(.light)
                        .frame(width: 18)
                }
            }
            .keyboardShortcut("1", modifiers: [.command])
            
            Toggle(isOn: Binding(
                get: { appState.currentMode == .global },
                set: { _ in Task { await appState.setMode(.global) } }
            )) {
                Label {
                    Text("Global")
                } icon: {
                    Image(systemName: "map")
                        .imageScale(.medium)
                        .fontWeight(.light)
                        .frame(width: 18)
                }
            }
            .keyboardShortcut("2", modifiers: [.command])
            
            Toggle(isOn: Binding(
                get: { appState.currentMode == .direct },
                set: { _ in Task { await appState.setMode(.direct) } }
            )) {
                Label {
                    Text("Direct")
                } icon: {
                    Image(systemName: "arrow.turn.up.right")
                        .imageScale(.medium)
                        .fontWeight(.light)
                        .frame(width: 18)
                }
            }
            .keyboardShortcut("3", modifiers: [.command])

        } label: {
            Label {
                Text("Mode")
            } icon: {
                Image(systemName: "arrow.triangle.branch")
                    .imageScale(.medium)
                    .fontWeight(.light)
                    .frame(width: 18)
            }
        }
        .keyboardShortcut("M", modifiers: [.command, .shift])
        
        // MITM Mode Toggle (Top Level)
        Toggle(isOn: Binding(
            get: { appState.mitmEnabled },
            set: { _ in appState.toggleMITM() }
        )) {
            Label {
                Text("MITM Mode")
            } icon: {
                Image(systemName: "eyeglasses")
                    .imageScale(.medium)
                    .fontWeight(.light)
                    .frame(width: 18)
            }
        }
        .keyboardShortcut("m", modifiers: [.command, .shift])
        
        Divider()
        
        Button(action: {
            NSApplication.shared.terminate(nil)
        }) {
            Label("Quit Ares", systemImage: "power")
        }
        .keyboardShortcut("q", modifiers: [.command])
    }
}
