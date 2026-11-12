import SwiftUI
import AppKit
import Combine

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var isTerminatingAfterCleanup = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableAutomaticTermination("Ares menu bar network service is active")

        // App started
        Task {
            // Initial health check and sync on launch
            await checkAndRecoverState()
        }

        AppUpdateService.shared.start()
        registerLifecycleObservers()
        registerWorkspaceObservers()

        // Handle Silent Start
        let silent = UserDefaults.standard.object(forKey: DefaultsKeys.silentStart) as? Bool ?? true
        if silent {
            ClashViewModel.shared.addLog("[AppDelegate] Silent start enabled - hiding application", level: .debug)
            // Hide the entire application from foreground
            DispatchQueue.main.async {
                NSApp.hide(nil)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Closing the workspace must not interrupt the proxy service.
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if AppTerminationCoordinator.shared.updateShutdownPrepared { return .terminateNow }
        guard !isTerminatingAfterCleanup else { return .terminateLater }

        isTerminatingAfterCleanup = true
        Task { @MainActor in
            let isSafeToTerminate = await AppTerminationCoordinator.shared.prepareForTermination()
            if !isSafeToTerminate {
                isTerminatingAfterCleanup = false
                NSApp.activate(ignoringOtherApps: true)
                NSApp.requestUserAttention(.criticalRequest)
                let alert = NSAlert()
                alert.alertStyle = .critical
                alert.messageText = "Ares could not finish shutting down"
                alert.informativeText = "Network restoration or core cleanup did not finish. Complete any authorization prompt, then try quitting again. See Logs for details."
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
            sender.reply(toApplicationShouldTerminate: isSafeToTerminate)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Force cleanup on exit
        ClashViewModel.shared.addLog("[AppDelegate] App terminating - cleaning up", level: .debug)

        // CRITICAL: Disable system proxy FIRST to prevent network outage
        // This must happen BEFORE we kill Clash, otherwise macOS traffic
        // will try to connect to a dead local port.
        SystemProxyManager.shared.disableAllProxiesSync()
        // NOTE: Keep systemProxyEnabled = true so proxy auto-restarts on next launch.
        // User's preference is preserved, only runtime state is cleaned up.

        ClashViewModel.shared.addLog("[AppDelegate] Cleanup complete", level: .debug)
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
        ClashViewModel.shared.addLog("[AppDelegate] Performing startup health check", level: .debug)

        // 0. Initialize State first (Loads Prefs, Check Privileges)
        await AppState.shared.initialize()
        await ClashViewModel.shared.refreshCoreVersion()
        Task {
            await ClashViewModel.shared.checkCoreUpdates()
        }

        // 1. Start Clash with retry capability (Gated)
        if ClashViewModel.shared.isRunning {
            ClashViewModel.shared.addLog("[AppDelegate] Clash is already running, skipping explicit start", level: .debug)
        } else {
            ClashViewModel.shared.addLog("[AppDelegate] Starting Clash", level: .debug)
            await ClashViewModel.shared.start()
        }

        // 2. Sync state with Clash immediately
        await AppState.shared.syncWithClash()

        // 3. Restore System Proxy state if enabled (NON-BLOCKING)
        // Run proxy setup in background to not delay app startup
        if AppState.shared.systemProxyEnabled && ClashViewModel.shared.runtimeState.isAPIReady {
            ClashViewModel.shared.addLog("[AppDelegate] Restoring system proxy state", level: .debug)
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

@MainActor
final class AppTerminationCoordinator {
    static let shared = AppTerminationCoordinator()

    private(set) var isCleaningUp = false

    private init() {}

    var updateShutdownPrepared = false

    func requestQuit() {
        NSApp.terminate(nil)
    }

    func prepareForTermination() async -> Bool {
        guard !isCleaningUp else { return false }
        isCleaningUp = true
        defer { isCleaningUp = false }

        // Block new actions and allow an already-running transition to settle.
        for _ in 0..<300 {
            if !ClashViewModel.shared.isToggling && AppState.shared.operationStatus == nil { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard !ClashViewModel.shared.isToggling, AppState.shared.operationStatus == nil else { return false }
        ClashViewModel.shared.addLog("[AppTermination] Preparing safe shutdown", level: .debug)

        guard SystemProxyManager.shared.disableAllProxiesSync() else {
            ClashViewModel.shared.addLog("[AppTermination] Failed to restore system proxy; keeping core alive", level: .error)
            return false
        }

        guard await ClashViewModel.shared.stopCore() else { return false }
        if NetworkMITMService.shared.isRunning {
            await NetworkMITMService.shared.stop()
        }

        AppState.shared.systemProxyEnabled = false
        AppState.shared.objectWillChange.send()

        ClashViewModel.shared.addLog("[AppTermination] Safe shutdown complete", level: .debug)
        return true
    }
}

/// Global accessor for the SwiftUI openWindow action.
/// Captured from MainView's onAppear so it can be used from MenuBarView.
@MainActor
enum WindowAccessor {
    static var openWindow: OpenWindowAction?

    static func showMainWindow(
        selection: AppState.NavigationItem?,
        openWindow action: OpenWindowAction? = nil
    ) {
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
                if let openWindowAction = action ?? openWindow {
                    openWindowAction(id: "main")
                }
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
                .onChange(of: scenePhase) { _, newPhase in
                    clashViewModel.addLog("[App] Scene phase changed to: \(newPhase)", level: .debug)
                    if newPhase == .active {
                        appState.wakeUp()
                    } else if newPhase == .background {
                        appState.goSilent()
                    }
                }
        }
        .commands {
            WorkspaceCommands(
                showSettings: { WindowAccessor.showMainWindow(selection: .settings) },
                showMainWindow: { WindowAccessor.showMainWindow(selection: nil) }
            )
            // Disable "New Window" to enforce single window behavior
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .appInfo) {
                AppUpdateMenuCommand()
            }
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
            MenuBarStatusLabel()
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarStatusLabel: View {
    @ObservedObject private var controller = ClashController.shared
    @ObservedObject private var runtime = ClashViewModel.shared
    @AppStorage(DefaultsKeys.menuBarShowsLatency) private var showsLatency = false

    var body: some View {
        AresMenuBarLabel(
            showsLatency: showsLatency,
            latency: runtime.isRunning ? controller.primaryLatency : nil
        )
        .help("Ares · \(runtime.runtimeState.title)")
    }
}

private struct AppUpdateMenuCommand: View {
    @ObservedObject private var updates = AppUpdateService.shared
    var body: some View {
        Button("Check for Updates…", action: updates.checkForUpdates)
            .disabled(!updates.canCheck || !updates.isConfigured)
    }
}
