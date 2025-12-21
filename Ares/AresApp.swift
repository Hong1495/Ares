import SwiftUI

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
        
        // Synchronous cleanup using sudo pkill directly
        // We use a direct Process call to avoid async/Task issues during termination
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        task.arguments = ["-n", "/usr/bin/pkill", "-9", "-f", "clash-meta"]
        try? task.run()
        task.waitUntilExit()
        
        print("✅ Cleanup command executed")
    }
    
    private func checkAndRecoverState() async {
        await Task.yield()
        print("🏥 Performing Startup Health Check...")
        
        // 0. Initialize State first (Loads Prefs, Check Privileges)
        await AppState.shared.initialize()
        
        // 1. Start Clash with retry capability
        print("🚀 Starting Clash...")
        await ClashViewModel.shared.start()
        
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
        WindowGroup {
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
        
        // Enhanced Menu Bar
        // Enhanced Menu Bar
        MenuBarExtra {
            Button(action: {
                NSApp.activate(ignoringOtherApps: true)
                appState.selection = .dashboard
                if let window = NSApp.windows.first {
                    window.makeKeyAndOrderFront(nil)
                }
            }) {
                Label("Dashboard", systemImage: "gauge.with.dots.needle.bottom.50percent")
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
                Label("System Proxy", systemImage: "network")
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            
            // TUN Mode Toggle
            Toggle(isOn: Binding(
                get: { appState.tunEnabled },
                set: { newValue in
                    print("[MenuBar] 🔘 TUN toggle clicked: \(appState.tunEnabled) -> \(newValue)")
                    appState.toggleTUN()
                }
            )) {
                Label("TUN Mode", systemImage: "bolt.shield.fill")
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            
            Divider()
            
            // Mode Selector
            Menu {
                Button(action: {
                    Task {
                        await appState.setMode(.rule)
                    }
                }) {
                    Label {
                        HStack {
                            Text("Rule")
                            if appState.currentMode == .rule {
                                Image(systemName: "checkmark")
                            }
                        }
                    } icon: {
                        Image(systemName: "list.bullet.rectangle")
                    }
                }
                .keyboardShortcut("1", modifiers: [.command])
                
                Button(action: {
                    Task {
                        await appState.setMode(.global)
                    }
                }) {
                    Label {
                        HStack {
                            Text("Global")
                            if appState.currentMode == .global {
                                Image(systemName: "checkmark")
                            }
                        }
                    } icon: {
                        Image(systemName: "globe")
                    }
                }
                .keyboardShortcut("2", modifiers: [.command])
                
                Button(action: {
                    Task {
                        await appState.setMode(.direct)
                    }
                }) {
                    Label {
                        HStack {
                            Text("Direct")
                            if appState.currentMode == .direct {
                                Image(systemName: "checkmark")
                            }
                        }
                    } icon: {
                        Image(systemName: "arrow.up.right.circle")
                    }
                }
                .keyboardShortcut("3", modifiers: [.command])
            } label: {
                Label("Mode", systemImage: "rhombus.fill")
            }
            .keyboardShortcut("M", modifiers: [.command, .shift])
            
            Divider()
            
            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                Label("Quit Ares", systemImage: "power")
            }
            .keyboardShortcut("q", modifiers: [.command])
        } label: {
            let proxyStatus = appState.systemProxyEnabled ? "1" : "0"
            let tunStatus = appState.tunEnabled ? "1" : "0"
            Image("Ares_Menu_\(proxyStatus)\(tunStatus)")
        }
    }
}
