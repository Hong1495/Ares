import SwiftUI
import AppKit

/// Intercepts window close to miniaturize instead of destroy.
/// miniaturize preserves frame perfectly (managed by macOS window system).
/// orderOut causes SwiftUI to tear down the view tree, losing window state.
class WindowCloseHandler: NSObject, NSWindowDelegate {
    weak var originalDelegate: NSWindowDelegate?

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.miniaturize(nil)
        return false
    }

    override func responds(to aSelector: Selector!) -> Bool {
        if aSelector == #selector(NSWindowDelegate.windowShouldClose(_:)) {
            return true
        }
        return originalDelegate?.responds(to: aSelector) ?? super.responds(to: aSelector)
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if aSelector == #selector(NSWindowDelegate.windowShouldClose(_:)) {
            return nil
        }
        return originalDelegate
    }
}

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

@main
struct AresApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    private let clashViewModel = ClashViewModel.shared
    private let profileService = ProfileService.shared
    private let clashController = ClashController.shared
    @StateObject private var appState = AppState.shared
    @StateObject private var themeService = ThemeService.shared
    @Environment(\.scenePhase) private var scenePhase

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
                    // Install close proxy on main window (hide instead of destroy)
                    // Uses proxy pattern to preserve SwiftUI's original delegate
                    DispatchQueue.main.async {
                        for window in NSApp.windows where window.styleMask.contains(.titled) && window.level == .normal {
                            if !(window.delegate is WindowCloseHandler) {
                                let handler = WindowCloseHandler()
                                handler.originalDelegate = window.delegate
                                window.delegate = handler
                            }
                        }
                    }
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
