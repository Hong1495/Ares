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
        let silent = UserDefaults.standard.bool(forKey: DefaultsKeys.silentStart)
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
        guard !isTerminatingAfterCleanup else { return .terminateNow }

        isTerminatingAfterCleanup = true
        Task { @MainActor in
            let isSafeToTerminate = await AppTerminationCoordinator.shared.prepareForTermination()
            if !isSafeToTerminate {
                isTerminatingAfterCleanup = false
                NSApp.activate(ignoringOtherApps: true)
                NSApp.requestUserAttention(.criticalRequest)
                let alert = NSAlert()
                alert.alertStyle = .critical
                alert.messageText = "Unable to restore network settings"
                alert.informativeText = "Ares is still running to keep the local proxy available. Disable System Proxy and try quitting again."
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
        if AppState.shared.systemProxyEnabled {
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

    private var isCleaningUp = false

    private init() {}

    var updateShutdownPrepared = false

    func requestQuit() {
        NSApp.terminate(nil)
    }

    func prepareForTermination() async -> Bool {
        guard !isCleaningUp, !ClashViewModel.shared.isToggling, AppState.shared.operationStatus == nil else { return false }
        isCleaningUp = true
        defer { isCleaningUp = false }

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
    @StateObject private var menuBarState = MenuBarIconProvider.shared
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
            MenuBarStatusLabel(state: menuBarState)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarStatusLabel: View {
    @ObservedObject var state: MenuBarIconProvider

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            dotView

            Text(state.latencyText)
                .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                .foregroundStyle(.primary)
        }
        .fixedSize()
    }

    @ViewBuilder
    private var dotView: some View {
        if state.isRunning && state.phase != 0 {
            Image(nsImage: state.dotImage)
                .renderingMode(.original)
                .frame(width: 7, height: 11, alignment: .center)
        } else {
            Image(nsImage: MenuBarIconProvider.standardDotImage)
                .renderingMode(.template)
                .foregroundColor(.primary.opacity(state.isRunning ? 0.9 : 0.35))
                .frame(width: 7, height: 11, alignment: .center)
        }
    }
}

// MARK: - Menu Bar Icon Provider

@MainActor
final class MenuBarIconProvider: ObservableObject {
    static let shared = MenuBarIconProvider()
    static let standardDotImage = renderStandardDot()

    @Published var icon: NSImage = NSImage(size: NSSize(width: 22, height: 22))
    @Published var dotImage: NSImage = NSImage(size: NSSize(width: 7, height: 11))
    @Published var latencyText = "-- ms"
    @Published var isRunning = false
    @Published var phase = 0
    @Published var statusColor = Color(red: 0.1, green: 0.55, blue: 1.0)

    private var pollingTask: Task<Void, Never>?
    private var cachedMs: Int? = nil
    private var cachedRunning = false
    private var cachedPhase = 0
    private var lastTestTime: Date = .distantPast

    private init() {
        icon = Self.render(ms: nil, isRunning: false, phase: 0)
        dotImage = Self.renderDot(ms: nil, isRunning: false, phase: 0)
        startPolling()
    }

    private func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { break }
                let vm = ClashViewModel.shared
                let ctrl = ClashController.shared
                let running = vm.isRunning

                if running {
                    // advance animation phase
                    phase = (phase + 1) % 4

                    // test latency every 5s
                    let now = Date()
                    if now.timeIntervalSince(lastTestTime) >= 5 {
                        if let name = ctrl.primaryNodeName {
                            _ = try? await ctrl.testProxyDelay(name: name, timeout: 2000)
                        }
                        lastTestTime = now
                    }
                }

                let ms = ctrl.primaryLatency
                let p = running ? phase : 0

                // only re-render on actual change
                if ms != cachedMs || running != cachedRunning || p != cachedPhase {
                    cachedMs = ms
                    cachedRunning = running
                    cachedPhase = p
                    isRunning = running
                    latencyText = ms.map { "\($0) ms" } ?? "-- ms"
                    statusColor = Self.statusColor(ms: ms)
                    icon = Self.render(ms: ms, isRunning: running, phase: p)
                    dotImage = Self.renderDot(ms: ms, isRunning: running, phase: p)
                }

                try? await Task.sleep(nanoseconds: 400_000_000)
            }
        }
    }

    private static func renderDot(ms: Int?, isRunning: Bool, phase: Int) -> NSImage {
        let size = NSSize(width: 7, height: 11)
        let dotSize: CGFloat = 5.5
        let image = NSImage(size: size)
        image.isTemplate = false

        image.lockFocus()
        defer { image.unlockFocus() }

        let fill: NSColor
        if isRunning {
            fill = phase == 0 ? NSColor.white.withAlphaComponent(0.9) : statusNSColor(ms: ms)
        } else {
            fill = NSColor.white.withAlphaComponent(0.35)
        }

        fill.setFill()
        let rect = NSRect(
            x: (size.width - dotSize) / 2,
            y: (size.height - dotSize) / 2,
            width: dotSize,
            height: dotSize
        )
        NSBezierPath(ovalIn: rect).fill()
        return image
    }

    private static func renderStandardDot() -> NSImage {
        let size = NSSize(width: 7, height: 11)
        let dotSize: CGFloat = 5.5
        let image = NSImage(size: size)
        image.isTemplate = true

        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.black.setFill()
        let rect = NSRect(
            x: (size.width - dotSize) / 2,
            y: (size.height - dotSize) / 2,
            width: dotSize,
            height: dotSize
        )
        NSBezierPath(ovalIn: rect).fill()
        return image
    }

    private static func render(ms: Int?, isRunning: Bool, phase: Int) -> NSImage {
        let text = ms.map { "\($0) ms" } ?? "-- ms"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .bold)
        ]
        let textSize = text.size(withAttributes: attrs)
        let dotSize: CGFloat = 7
        let dotX: CGFloat = 1
        let textGap: CGFloat = 6
        let trailingPadding: CGFloat = 2
        let size = NSSize(width: ceil(dotX + dotSize + textGap + textSize.width + trailingPadding), height: 22)
        let image = NSImage(size: size)
        image.isTemplate = false

        image.lockFocus()
        defer { image.unlockFocus() }

        let menuBarForeground = NSColor.white.withAlphaComponent(0.92)
        let menuBarSecondary = NSColor.white.withAlphaComponent(0.45)
        let statusColor = statusNSColor(ms: ms)

        // --- status dot ---
        let dotsTotalW = dotSize
        let dotsX = dotX
        let dotsY: CGFloat = (size.height - dotSize) / 2

        let rect = NSRect(x: dotsX, y: dotsY, width: dotSize, height: dotSize)
        let path = NSBezierPath(ovalIn: rect)
        let fill: NSColor
        if isRunning {
            fill = phase == 0 ? statusColor : menuBarForeground
        } else {
            fill = menuBarSecondary.withAlphaComponent(0.35)
        }
        fill.setFill()
        path.fill()

        // --- latency text ---
        let textX = dotsX + dotsTotalW + textGap
        let textColor: NSColor = ms == nil ? menuBarSecondary : menuBarForeground
        let drawAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .bold),
            .foregroundColor: textColor
        ]
        let textY = (size.height - textSize.height) / 2
        text.draw(at: NSPoint(x: textX, y: textY), withAttributes: drawAttrs)

        return image
    }

    private static func statusColor(ms: Int?) -> Color {
        guard let ms = ms else { return Color(red: 0.1, green: 0.55, blue: 1.0) }
        if ms < 200 { return Color(red: 0.0, green: 0.9, blue: 0.28) }
        if ms < 500 { return Color(red: 1.0, green: 0.72, blue: 0.0) }
        return Color(red: 1.0, green: 0.18, blue: 0.12)
    }

    private static func statusNSColor(ms: Int?) -> NSColor {
        guard let ms = ms else { return NSColor(red: 0.1, green: 0.55, blue: 1.0, alpha: 1) }
        if ms < 200 { return NSColor(red: 0.0, green: 0.9, blue: 0.28, alpha: 1) }
        if ms < 500 { return NSColor(red: 1.0, green: 0.72, blue: 0.0, alpha: 1) }
        return NSColor(red: 1.0, green: 0.18, blue: 0.12, alpha: 1)
    }
}

private struct AppUpdateMenuCommand: View {
    @ObservedObject private var updates = AppUpdateService.shared
    var body: some View {
        Button("Check for Updates…", action: updates.checkForUpdates)
            .disabled(!updates.canCheck || !updates.isConfigured)
    }
}
