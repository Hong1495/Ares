import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // App started
        Task {
            // Initial health check and sync on launch
            await checkAndRecoverState()
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
        print("🏥 Performing Startup Health Check...")
        
        // 0. Initialize State first (Loads Prefs, Check Privileges)
        await AppState.shared.initialize()
        
        // 1. Start Clash with retry capability
        print("🚀 Starting Clash...")
        await ClashViewModel.shared.start()
        
        // 1.1 First-run health check: if not running, wait and retry once
        try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s wait to stabilize
        if !ClashViewModel.shared.isRunning {
            print("⚠️ Initial Clash start failed or slow, retrying...")
            await ClashViewModel.shared.stop()
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await ClashViewModel.shared.start()
        }
        
        // 2. Sync state with Clash
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
    
    @StateObject private var clashViewModel = ClashViewModel.shared
    @StateObject private var profileService = ProfileService.shared
    @StateObject private var clashController = ClashController.shared
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
        }
        
        // Enhanced Menu Bar
        MenuBarExtra("Ares", systemImage: "bolt.shield.fill") {
            // System Proxy Toggle
            Toggle("System Proxy", isOn: Binding(
                get: { appState.systemProxyEnabled },
                set: { _ in
                    Task {
                        await appState.toggleSystemProxy()
                    }
                }
            ))
            .keyboardShortcut("p", modifiers: [.command, .shift])
            
            // TUN Mode Toggle
            Toggle("TUN Mode", isOn: Binding(
                get: { appState.tunEnabled },
                set: { newValue in
                    print("[MenuBar] 🔘 TUN toggle clicked: \(appState.tunEnabled) -> \(newValue)")
                    print("[MenuBar] 📞 Calling toggleTUN()")
                    appState.toggleTUN()
                    print("[MenuBar] ✅ toggleTUN() called")
                }
            ))
            .keyboardShortcut("t", modifiers: [.command, .shift])
            
            Divider()
            
            // Mode Selector
            Menu("Mode") {
                Button(action: {
                    Task {
                        await appState.setMode(.rule)
                    }
                }) {
                    HStack {
                        Text("Rule")
                        if appState.currentMode == .rule {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .keyboardShortcut("1", modifiers: [.command])
                
                Button(action: {
                    Task {
                        await appState.setMode(.global)
                    }
                }) {
                    HStack {
                        Text("Global")
                        if appState.currentMode == .global {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .keyboardShortcut("2", modifiers: [.command])
                
                Button(action: {
                    Task {
                        await appState.setMode(.direct)
                    }
                }) {
                    HStack {
                        Text("Direct")
                        if appState.currentMode == .direct {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .keyboardShortcut("3", modifiers: [.command])
            }
            .keyboardShortcut("M", modifiers: [.command, .shift])
            
            Divider()
            
            Button("Dashboard") {
                NSApp.activate(ignoringOtherApps: true)
                // Just bringing window to front, usually handled by Dock icon click
                if let window = NSApp.windows.first {
                    window.makeKeyAndOrderFront(nil)
                }
            }
            .keyboardShortcut("d", modifiers: [.command])
            
            Divider()
            
            Button("Quit Ares") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: [.command])
        }
    }
}
