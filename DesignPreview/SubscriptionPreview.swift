import SwiftUI
import Combine
import SubscriptionKit

// Only this mock file supplies service types. No production service or app delegate
// is linked. The actual ProxiesView reads a synthetic subscription from a temp file.
@MainActor final class ClashController: ObservableObject {
    @Published var runtimeGeneration = UUID()
    func queryDNS(name: String, type: String) async throws -> DNSQueryResult {
        try JSONDecoder().decode(DNSQueryResult.self, from: Data(#"{"Status":0,"TC":false,"Answer":[{"name":"fixture.test.","type":1,"TTL":90,"data":"192.0.2.10"}]}"#.utf8))
    }
    func fetchProxyResources() async throws -> [ProxyResource] {
        try ProxyResource.decode(Data(#"{"providers":{"Sample Resource":{"name":"Sample Resource","vehicleType":"HTTP","updatedAt":"2026-11-13T01:00:00Z","proxies":[{"name":"Sample 1","type":"VLESS","alive":true,"history":[{"time":"2026-11-13T01:00:00Z","delay":35}]}]}}}"#.utf8))
    }
    func performProxyResourceAction(name: String, healthCheck: Bool) async throws -> [ProxyResource] { try await fetchProxyResources() }
    @Published var testingProxyNames: Set<String> = []
    @Published var isTestingAllProxies = false
    func testAllProxyDelays() async { fatalError("Offline testing must be disabled") }
    @Published var proxyGroups: [ProxyGroup] = []
    @Published var proxyNodes: [String: ProxyNode] = [:]
    func fetchProxiesData() async throws { fatalError("Offline preview must never call the core") }
    func selectProxy(group: String, proxy: String) async throws { fatalError("Offline selection must be disabled") }
    func testProxyDelay(name: String) async throws -> Int { fatalError("Offline latency testing must be disabled") }
}
@MainActor final class ClashViewModel: ObservableObject {
    @Published var appliedProfileRevision = ""
    @Published var runtimeState = "stopped"
    @Published var isRunning = false
    @Published var isToggling = false
    func start() async { fatalError("Preview must not start a core") }
}
struct PreviewProfile {
    let id = UUID()
    let path: URL?
    let lastUpdated: Date? = Date()
}
@MainActor final class ProfileService: ObservableObject {
    @Published var activeProfile: PreviewProfile?
    @Published private var choices: [String: String] = [:]
    var activeProfileRevision: String { activeProfile?.id.uuidString ?? "" }
    func savedNode(group: String) -> String? { choices[group] }
    func clearNodeSelection(group: ProxyGroup) async throws { choices.removeValue(forKey: group.name) }
    func selectNode(group: ProxyGroup, node: String) async throws { choices[group.name] = node }
    init() {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("ares-offline-preview-\(UUID()).yaml")
        let nodes = (1...32).map { "  - {name: Sample \($0), type: vless, server: example.invalid, port: 443}" }.joined(separator: "\n")
        let members = (1...32).map { "Sample \($0)" }.joined(separator: ", ")
        try! "proxies:\n\(nodes)\nproxy-groups:\n  - {name: Select, type: select, proxies: [\(members)]}\n  - {name: Auto, type: url-test, proxies: [\(members)]}".write(to: path, atomically: true, encoding: .utf8)
        activeProfile = PreviewProfile(path: path)
    }
    isolated deinit { if let path = activeProfile?.path { try? FileManager.default.removeItem(at: path) } }
}
@MainActor final class AppState: ObservableObject {
    @Published var currentMode: ClashConfig.Mode = .rule
    var isPerformingNetworkOperation = false
    func setMode(_ mode: ClashConfig.Mode) async { currentMode = mode }
    static let shared = AppState()
    var lastOperationError: String?
    func beginOperation(_ message: String) -> Bool { true }
    func finishOperation(error: String?) {}
    func reportError(_ message: String) { assertionFailure(message) }
}
@MainActor enum PolicyGroupService {
    struct Snapshot {
        let revision: String
        let storageKey: String
        let stored: String
        let inherited: [PolicyConfiguration.Group]
        let effective: [PolicyConfiguration.Group]
    }
    static var canReadRuntime: Bool { false }
    static func load() async throws -> Snapshot {
        let groups = try PolicyConfiguration.read("proxy-groups: [{name: Automatic, type: url-test, proxies: [Sample 1], interval: 600, tolerance: 50, use: [Sample Resource]}]")
        return Snapshot(revision: "preview", storageKey: "unused", stored: "{}", inherited: groups, effective: groups)
    }
    static func apply(_ text: String, snapshot: Snapshot) async -> Bool { false }
}
@MainActor enum DNSSettingsService {
    struct Snapshot {
        let revision: String
        let storageKey: String
        let stored: String
        let inherited: [String: String]
        let effective: [String: String]
        let sources: [String: String]
    }
    static var canReadRuntime: Bool { true }
    static func load() async throws -> Snapshot {
        let values = ["nameserver-policy": "'+.internal.test': [192.0.2.53]", "enhanced-mode": "fake-ip", "respect-rules": "false"]
        return Snapshot(revision: "preview", storageKey: "unused", stored: "{}", inherited: values, effective: values, sources: values.mapValues { _ in "Subscription" })
    }
    static func apply(_ text: String, snapshot: Snapshot) async -> Bool { false }
}
@MainActor enum EgressSettingsService {
    struct Snapshot {
        let revision: String
        let storageKey: String
        let stored: String
        let inherited: EgressConfiguration.Document
        let effective: EgressConfiguration.Document
    }
    static func load() async throws -> Snapshot {
        let document = try EgressConfiguration.read("proxies: [{name: Entry, type: http}, {name: Exit, type: vless, dialer-proxy: Entry}]")
        return Snapshot(revision: "preview", storageKey: "unused", stored: EgressConfiguration.empty, inherited: document, effective: document)
    }
    static func apply(_ text: String, snapshot: Snapshot) async -> Bool { false }
}
@MainActor enum ScenarioService {
    struct Context { let profileID: UUID; let revision: String; let settings: ScenarioSettings }
    struct Review: Identifiable {
        let id = UUID()
        let name: String
        let context: Context
        let target: ScenarioSettings
        let sourceChanged: Bool
        let isUndo: Bool
        var changes: [ScenarioSettings.Difference] { target.differences(from: context.settings) }
    }
    static let id = UUID()
    static let settings = ScenarioSettings(localRules: nil, dns: nil, policy: nil, egress: nil)
    static func context() throws -> Context { Context(profileID: id, revision: "preview", settings: settings) }
    static func list() throws -> [ManualScenario] {
        [try ManualScenario(name: "Office", profileID: id, sourceRevision: "preview", settings: ScenarioSettings(localRules: "MATCH,DIRECT", dns: "{}", policy: nil, egress: nil))]
    }
    static func save(name: String, expected: Context) throws {}
    static func remove(_ scenario: ManualScenario) throws {}
    static func review(_ scenario: ManualScenario) throws -> Review {
        Review(name: scenario.name, context: try context(), target: scenario.settings, sourceChanged: false, isUndo: false)
    }
    static func undoReview() -> Review? { nil }
    static func apply(_ review: Review) async -> Bool { false }
}
@MainActor enum ActivityDiagnosticsService {
    struct Row: Identifiable { let id: String; let status: String; let detail: String; let attention: Bool }
    struct Snapshot { let capturedAt: Date; let rows: [Row] }
    static func load() async throws -> Snapshot {
        Snapshot(capturedAt: Date(), rows: [
            Row(id: "Subscription", status: "Matches", detail: "Running revision matches the selected subscription.", attention: false),
            Row(id: "Node resources", status: "Unavailable", detail: "Resource metadata could not be read.", attention: true),
            Row(id: "Policy membership", status: "No static issues", detail: "4 groups · 32 member references", attention: false)])
    }
}
struct RuleSourcesView: View { var body: some View { Text("Inert rule sources preview") } }
@main struct SubscriptionPreview: App {
    @State private var showingSettings = false
    @Environment(\.openWindow) private var openWindow
    @StateObject private var controller = ClashController()
    @StateObject private var profiles = ProfileService()
    @StateObject private var runtime = ClashViewModel()
    var body: some Scene {
        WindowGroup("Ares · Offline subscription preview", id: "main") {
            Group {
                if CommandLine.arguments.contains("--scenes") { ScenariosView().frame(width: 740, height: 500) }
                else if CommandLine.arguments.contains("--diagnostics") { ActivityDiagnosticsView().frame(width: 800, height: 520) }
                else if CommandLine.arguments.contains("--egress") { EgressSettingsView().frame(width: 740, height: 560) }
                else if CommandLine.arguments.contains("--dns") { DNSSettingsView().frame(width: 740, height: 540) }
                else if CommandLine.arguments.contains("--resources") { ProxyResourcesView() }
                else if CommandLine.arguments.contains("--policies") { PolicyGroupsView() }
                else { ProxiesView() }
            }
                .environmentObject(controller)
                .environmentObject(profiles)
                .environmentObject(runtime)
                .environmentObject(AppState.shared)
                .frame(minWidth: CommandLine.arguments.contains("--dns") ? 740 : 1000, minHeight: CommandLine.arguments.contains("--dns") ? 540 : 700)
                .alert("Settings preview", isPresented: $showingSettings) {
                    Button("Done", role: .cancel) { }
                } message: { Text("Native Settings menu action received. No production service is running.") }
        }.defaultSize(width: CommandLine.arguments.contains("--dns") ? 740 : 1100, height: CommandLine.arguments.contains("--dns") ? 540 : 760)
        .commands {
            WorkspaceCommands(showSettings: { showingSettings = true }, showMainWindow: { openWindow(id: "main") })
        }
    }
}
