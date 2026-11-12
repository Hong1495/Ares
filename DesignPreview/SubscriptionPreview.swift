import SwiftUI
import Combine

// Only this mock file supplies service types. No production service or app delegate
// is linked. The actual ProxiesView reads a synthetic subscription from a temp file.
@MainActor final class ClashController: ObservableObject {
    @Published var proxyGroups: [ProxyGroup] = []
    @Published var proxyNodes: [String: ProxyNode] = [:]
    func fetchProxiesData() async throws { fatalError("Offline preview must never call the core") }
    func selectProxy(group: String, proxy: String) async throws { fatalError("Offline selection must be disabled") }
    func testProxyDelay(name: String) async throws -> Int { fatalError("Offline latency testing must be disabled") }
}
@MainActor final class ClashViewModel: ObservableObject {
    @Published var isRunning = false
    @Published var isToggling = false
}
struct PreviewProfile {
    let id = UUID()
    let path: URL?
    let lastUpdated: Date? = Date()
}
@MainActor final class ProfileService: ObservableObject {
    @Published var activeProfile: PreviewProfile?
    init() {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("ares-offline-preview-\(UUID()).yaml")
        let nodes = (1...32).map { "  - {name: Sample \($0), type: vless, server: example.invalid, port: 443}" }.joined(separator: "\n")
        let members = (1...32).map { "Sample \($0)" }.joined(separator: ", ")
        try! "proxies:\n\(nodes)\nproxy-groups:\n  - {name: Select, type: select, proxies: [\(members)]}\n  - {name: Auto, type: url-test, proxies: [\(members)]}".write(to: path, atomically: true, encoding: .utf8)
        activeProfile = PreviewProfile(path: path)
    }
    isolated deinit { if let path = activeProfile?.path { try? FileManager.default.removeItem(at: path) } }
}
@MainActor final class AppState {
    static let shared = AppState()
    func reportError(_ message: String) { assertionFailure(message) }
}
@main struct SubscriptionPreview: App {
    @State private var showingSettings = false
    @Environment(\.openWindow) private var openWindow
    @StateObject private var controller = ClashController()
    @StateObject private var profiles = ProfileService()
    @StateObject private var runtime = ClashViewModel()
    var body: some Scene {
        WindowGroup("Ares · Offline subscription preview", id: "main") {
            ProxiesView()
                .environmentObject(controller)
                .environmentObject(profiles)
                .environmentObject(runtime)
                .frame(minWidth: 1000, minHeight: 700)
                .alert("Settings preview", isPresented: $showingSettings) {
                    Button("Done", role: .cancel) { }
                } message: { Text("Native Settings menu action received. No production service is running.") }
        }.defaultSize(width: 1100, height: 760)
        .commands {
            WorkspaceCommands(showSettings: { showingSettings = true }, showMainWindow: { openWindow(id: "main") })
        }
    }
}
