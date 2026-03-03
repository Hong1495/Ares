import SwiftUI
import AppKit

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // App started
        Task {
            // Initial health check and sync on launch
            await checkAndRecoverState()
        }

        registerLifecycleObservers()
        registerWorkspaceObservers()

        // Handle Silent Start
        let silent = UserDefaults.standard.bool(forKey: DefaultsKeys.silentStart)
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
        if UserDefaults.standard.bool(forKey: DefaultsKeys.systemProxyEnabled) {
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

    /// Called when user clicks Dock icon while app is running
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            // No visible windows — reopen main window
            WindowAccessor.showMainWindow(selection: nil)
        }
        return true
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

    private func registerLifecycleObservers() {
        let center = NotificationCenter.default
        lifecycleObservers.append(
            center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
                Task { @MainActor in
                    AppState.shared.wakeUp()
                }
            }
        )
        lifecycleObservers.append(
            center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
                Task { @MainActor in
                    AppState.shared.goSilent()
                }
            }
        )
    }

    private func registerWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(
            center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                let isSelf = app.bundleIdentifier == Bundle.main.bundleIdentifier
                Task { @MainActor in
                    if isSelf {
                        AppState.shared.wakeUp()
                    } else {
                        AppState.shared.goSilent()
                    }
                }
            }
        )
    }
}

/// Global accessor for the SwiftUI openWindow action.
/// Captured from MainView's onAppear so it can be used from MenuBarView.
@MainActor
enum WindowAccessor {
    static var openWindow: OpenWindowAction?

    static func showMainWindow(selection: AppState.NavigationItem?) {
        if let selection = selection {
            AppState.shared.selection = selection
        }

        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)

            // Find existing main window
            let mainWindow = NSApp.windows.first(where: { window in
                guard window.styleMask.contains(.titled), window.level == .normal else { return false }
                let id = window.identifier?.rawValue ?? ""
                if id == "network-inspector" { return false }
                return true
            })

            if let window = mainWindow {
                if window.isMiniaturized {
                    window.deminiaturize(nil)
                }
                window.makeKeyAndOrderFront(nil)
            } else {
                // Window was closed (destroyed by SwiftUI) — create a new one
                openWindow?(id: "main")
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
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openWindow) private var openWindow

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
                    // Capture openWindow for use from MenuBarView
                    WindowAccessor.openWindow = openWindow
                }
                .preferredColorScheme(themeService.theme == "dark" ? .dark : (themeService.theme == "light" ? .light : nil))
                .onChange(of: scenePhase) { newPhase in
                    print("[App] 🎬 Scene Phase changed to: \(newPhase)")
                    if newPhase == .active {
                        appState.wakeUp()
                    } else if newPhase == .background {
                        appState.goSilent()
                    }
                }
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
            MenuBarView(appState: appState, clashViewModel: clashViewModel)
                .environmentObject(clashController)
        } label: {
            let proxyStatus = appState.systemProxyEnabled ? "1" : "0"
            let tunStatus = appState.tunEnabled ? "1" : "0"
            Image("Ares_Menu_\(proxyStatus)\(tunStatus)")
        }
        .menuBarExtraStyle(.window)
    }
}
