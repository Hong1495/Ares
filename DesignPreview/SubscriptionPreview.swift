import SwiftUI
import Combine
import SubscriptionKit

// Only this mock file supplies service types. No production service or app delegate
// is linked. The actual ProxiesView reads a synthetic subscription from a temp file.
@MainActor final class ClashController: ObservableObject {
    struct Chain {
        let sourceProcess: String, rule: String, host: String, destinationIP: String
        let chains: [String]
    }
    static let shared = ClashController()
    var activeChains: [Chain] { (1...80).map { Chain(sourceProcess: "Preview App", rule: "Domain", host: "fixture-\($0).test", destinationIP: "", chains: ["Preview Route"]) } }
    func monitorConnections() async {}
    init() {
        let activity = ResourceActivity.shared
        let attempt = try! activity.begin(name: "Sample Resource", kind: .nodes, action: .update, generation: runtimeGeneration, endpoint: baseURL)
        activity.advance(attempt, to: .reading)
        activity.finish(attempt, error: URLError(.timedOut))
    }
    let baseURL = "https://preview.invalid"
    @Published var rules: [ClashRule] = []
    func fetchRules() async throws {}
    func fetchRuleProviders() async throws -> [RuleProvider] {
        try RuleProvider.decode(Data(#"{"providers":{"Sample Rules":{"name":"Sample Rules","behavior":"domain","vehicleType":"HTTP","ruleCount":128}}}"#.utf8))
    }
    func updateRuleProvider(_ name: String) async throws -> [RuleProvider] { try await fetchRuleProviders() }
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
    static let shared = ProfileService()
    var activeProfileID: UUID? { activeProfile?.id }
    func createResourceWorkspace() throws {}
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
    enum NavigationItem { case policies, scenes }
    var selection = NavigationItem.policies
    @Published var currentMode: ClashConfig.Mode = .rule
    var animationsEnabled = false
    var isForeground = true
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
        var source = "proxies: [{name: Sample 1, type: vless, server: example.invalid, port: 443}]\nproxy-groups: [{name: Automatic, type: url-test, proxies: [Sample 1]}]"
        var localRules = ""
    }
    static var canReadRuntime: Bool { false }
    static func load() async throws -> Snapshot {
        let groups = try PolicyConfiguration.read("proxy-groups: [{name: Automatic, type: url-test, proxies: [Sample 1], interval: 600, tolerance: 50, use: [Sample Resource]}]")
        return Snapshot(revision: "preview", storageKey: "unused", stored: "{}", inherited: groups, effective: groups)
    }
    static func apply(_ text: String, snapshot: Snapshot, localRules: String? = nil) async -> Bool { false }
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
@MainActor enum SceneCatalogService {
    struct Catalog { let groups: [ProxyGroup]; let live: Bool; let revision: String }
    static func load() async throws -> Catalog {
        .init(groups: [.init(name: "Select", type: "Selector", all: ["Tokyo", "Singapore", "Auto"])], live: true, revision: "preview")
    }
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
    static func history() throws -> [SceneExecution] { [.init(sceneID: nil, name: "Office", automatic: false, result: "Applied and verified", sections: ["DNS", "Proxy Mode"])] }
    static func context() throws -> Context { Context(profileID: id, revision: "preview", settings: settings) }
    static func list() throws -> [ManualScenario] {
        let scrolling = CommandLine.arguments.contains("--scroll-preview")
        let rules = scrolling ? (1...80).map { "DOMAIN,fixture-\($0).test,DIRECT" }.joined(separator: "\n") : "MATCH,DIRECT"
        return try (1...(scrolling ? 40 : 1)).map {
            try ManualScenario(name: scrolling ? "Office \($0)" : "Office", profileID: id, sourceRevision: "preview", settings: ScenarioSettings(localRules: rules, dns: "{}", policy: nil, egress: nil))
        }
    }
    static func save(name: String, expected: Context) throws {}
    static func remove(_ scenario: ManualScenario) throws {}
    static func update(_ original: ManualScenario, name: String, settings: ScenarioSettings, expected: Context, trigger: SceneTrigger? = nil) throws {}
    static func review(_ scenario: ManualScenario) throws -> Review {
        Review(name: scenario.name, context: try context(), target: scenario.settings, sourceChanged: false, isUndo: false)
    }
    static func undoReview() -> Review? { nil }
    static func apply(_ review: Review) async -> Bool { false }
}
@MainActor final class SceneAutomationService: ObservableObject {
    static let shared = SceneAutomationService()
    @Published var enabled = false
    @Published var paused = false
    @Published var status = "Automatic switching is off"
    var environment = SceneEnvironment(available: true, kind: "wifi", interface: "en0", expensive: false, constrained: false)
    var rows: [SceneMatcher.Row] { [.init(id: UUID(), name: "Office", priority: 10, reason: "All conditions match", matches: true)] }
    func start() {}
    func setEnabled(_ value: Bool) { enabled = value }
    func pause() { paused = true }
    func resume() { paused = false }
}
@MainActor enum ActivityDiagnosticsService {
    enum Destination: Equatable, Identifiable {
        var id: String { String(describing: self) }
        case configuration, policies, nodes(String?), rules(String?), sources(String?), history }
    struct Row: Identifiable { let id: String; let status: String; let detail: String; let attention: Bool; var destination: Destination? = nil }
    struct Snapshot { let capturedAt: Date; let rows: [Row]; var audit: [ConfigurationAudit.Row] = []; var differences: [ConfigurationDiff.Row] = [] }
    static func load() async throws -> Snapshot {
        Snapshot(capturedAt: Date(), rows: [
            Row(id: "Saved configuration", status: "Different", detail: "One structural difference from verified launch.", attention: true, destination: .configuration),
            Row(id: "Nodes · Sample Resource", status: "Read", detail: "32 nodes · 28 measured · Historical measurements, not a live connectivity test.", attention: false, destination: .nodes("Sample Resource")),
            Row(id: "Rules · Sample Rules", status: "Read", detail: "128 rules · domain · 2 configured references.", attention: false, destination: .rules("Sample Rules")),
            Row(id: "Policy membership", status: "No static issues", detail: "4 groups · 32 member references", attention: false, destination: .policies),
            Row(id: "Last nodes operation · Sample Resource", status: "Unconfirmed", detail: "Update · The core may have completed the request. Read current metadata before retrying.", attention: true, destination: .history)])
    }
}
struct RuleSourcesView: View { var provider: String? = nil; var body: some View { Text("Inert rule sources preview") } }
@main struct SubscriptionPreview: App {
    @State private var showingSettings = false
    @Environment(\.openWindow) private var openWindow
    @StateObject private var controller = ClashController()
    @StateObject private var profiles = ProfileService()
    @StateObject private var runtime = ClashViewModel()
    var body: some Scene {
        WindowGroup("Ares · Offline subscription preview", id: CommandLine.arguments.contains("--compact") ? "compact-" + (CommandLine.arguments.dropFirst().first ?? "main") : "main") {
            Group {
                if CommandLine.arguments.contains("--managed") { ManagedResourcesView() }
                else if CommandLine.arguments.contains("--devices") { DevicesView() }
                else if CommandLine.arguments.contains("--topology") { TopologyPageView() }
                else if CommandLine.arguments.contains("--scenes") { ScenariosView(embedded: true).toolbar { CollectionTitleToolbar(title: "Scenes", count: nil, unit: "") } }
                else if CommandLine.arguments.contains("--diagnostics") { ActivityDiagnosticsView().frame(width: 800, height: 520) }
                else if CommandLine.arguments.contains("--quality") { ScrollView { NetworkQualityView(embedded: true) }.toolbar { CollectionTitleToolbar(title: "Network Quality", count: nil, unit: "") } }
                else if CommandLine.arguments.contains("--apps") { ApplicationRoutingView(embedded: true, initialPaths: ["/Applications/Preview.app/Contents/MacOS/Preview"]).toolbar { CollectionTitleToolbar(title: "Applications", count: nil, unit: "") } }
                else if CommandLine.arguments.contains("--egress") { EgressSettingsView().frame(width: 740, height: 560) }
                else if CommandLine.arguments.contains("--dns") { DNSSettingsView().frame(width: 740, height: 540) }
                else if CommandLine.arguments.contains("--resources") { ProxyResourcesView() }
                else if CommandLine.arguments.contains("--policies") { PolicyGroupsView(embedded: true) }
                else { ProxiesView() }
            }
                .scrollIndicators(.never, axes: [.horizontal, .vertical])
                .environmentObject(controller)
                .environmentObject(profiles)
                .environmentObject(runtime)
                .environmentObject(AppState.shared)
                .frame(minWidth: CommandLine.arguments.contains("--compact") ? 680 : CommandLine.arguments.contains("--dns") ? 740 : 1000, minHeight: CommandLine.arguments.contains("--compact") || CommandLine.arguments.contains("--dns") ? 540 : 700)
                .alert("Settings preview", isPresented: $showingSettings) {
                    Button("Done", role: .cancel) { }
                } message: { Text("Native Settings menu action received. No production service is running.") }
        }.defaultSize(width: CommandLine.arguments.contains("--compact") ? 680 : CommandLine.arguments.contains("--dns") ? 740 : 1100, height: CommandLine.arguments.contains("--compact") || CommandLine.arguments.contains("--dns") ? 540 : 760)
        .commands {
            WorkspaceCommands(showSettings: { showingSettings = true }, showMainWindow: { openWindow(id: "main") })
        }
    }
}

@MainActor final class NetworkQualityService: ObservableObject {
    static let shared = NetworkQualityService()
    struct Target: Identifiable { let id: String; let name: String }
    static let targets = [Target(id: "gstatic", name: "Google"), Target(id: "cloudflare", name: "Cloudflare"), Target(id: "github", name: "GitHub")]
    @Published var enabled = true
    @Published var group = "Preview Auto"
    @Published var interval = 60
    @Published var window = NetworkQuality.Window()
    @Published var groups = [ProxyGroup(name: "Preview Auto", type: "URLTest", now: "Sample 1", all: ["Sample 1", "Sample 2"])]
    var status = "Synthetic preview · not production measurements"
    var observedAt: Date? = Date()
    var error: String?
    init() {
        for n in 0..<20 { window.record(.init(date: Date().addingTimeInterval(Double(n - 20) * 60), milliseconds: n == 10 ? nil : 70 + n % 7 * 15, outcome: "Preview fixture"), target: "gstatic") }
        window.observe(.init(path: [group, "Sample 1"], pinned: false, kind: "URLTest"))
        window.observe(.init(path: [group, "Sample 2"], pinned: false, kind: "URLTest"))
    }
    func start() {}
    func readGroups() async {}
    func setEnabled(_ value: Bool) { enabled = value }
    func configure(group: String, interval: Int) { self.group = group; self.interval = interval }
    func reset() { window = .init() }
    func select(member: String) async {}
    func resumeAutomatic(group: String) async {}
}
@MainActor enum ApplicationRoutingService {
    struct Snapshot {
        let policy: PolicyGroupService.Snapshot
        let rules: String
        let evidence: [String]
        let evidenceSource: String
        let targets: [String]
    }
    struct Undo { let previous: String; let applied: String; let revision: String }
    static func load() async throws -> Snapshot {
        Snapshot(policy: try await PolicyGroupService.load(), rules: "", evidence: ["PROCESS-PATH,/Applications/Preview.app/Contents/MacOS/Preview,DIRECT", "MATCH,Automatic"], evidenceSource: "Synthetic preview", targets: ["DIRECT", "REJECT", "Automatic"])
    }
    static func apply(paths: [String], target: String?, snapshot: Snapshot) async throws -> Undo? { nil }
    static func undo(_ undo: Undo) async -> Bool { true }
    static func connections() async throws -> [Connection] { [] }
}

@MainActor enum ManagedWorkspaceService {
    struct Document: Equatable { var resources = ManagedResources.Draft(); var devices: [DeviceAccess.Device] = [] }
    struct Snapshot {
        let document: Document
        let source: String
        var targets: [String] { ["DIRECT", "Automatic", "Work"] }
    }
    static var saved = Document(devices: [.init(name: "Phone", enabled: true, address: "192.0.2.10", port: 10810, username: "phone", password: "preview-only-credential", target: "Automatic"), .init(name: "Tablet", username: "tablet", password: "preview-only-credential")])
    static func read(_ id: UUID?) throws -> Document { saved }
    static func load() async throws -> Snapshot {
        Snapshot(document: saved, source: "proxies: [{name: Personal, type: vless, server: example.invalid, port: 443, uuid: 11111111-1111-1111-1111-111111111111, tls: true}]\nproxy-providers: {Work: {type: http, url: 'https://example.invalid/nodes', interval: 3600}}")
    }
    static func apply(_ document: Document, snapshot: Snapshot) async throws { saved = document }
}
