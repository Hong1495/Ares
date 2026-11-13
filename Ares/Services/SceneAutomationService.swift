import Foundation
import Network
import Combine

/// Explicit opt-in, current subscription only. Never starts a stopped core or toggles proxy/TUN.
@MainActor final class SceneAutomationService: ObservableObject {
    static let shared = SceneAutomationService()
    @Published private(set) var environment = SceneEnvironment.unknown
    @Published private(set) var status = "Automatic switching is off"
    @Published private(set) var enabled: Bool
    @Published private(set) var paused: Bool
    @Published private(set) var rows: [SceneMatcher.Row] = []
    private let defaults: UserDefaults
    private let monitorsNetwork: Bool
    init(defaults: UserDefaults = .standard, monitorsNetwork: Bool = true) {
        self.defaults = defaults; self.monitorsNetwork = monitorsNetwork
        enabled = defaults.bool(forKey: "sceneAutomation.enabled")
        paused = defaults.bool(forKey: "sceneAutomation.paused")
        if paused { status = "Paused · Resume to evaluate the current network" }
    }
    private var monitor: NWPathMonitor?
    private var loop: Task<Void, Never>?
    private var manualObserver: NSObjectProtocol?
    private var debounce = SceneDebounce()
    private var lastApplied: ScenarioService.Context?
    private var applying = false
    private var epoch = UUID()

    func start() {
        guard monitorsNetwork, monitor == nil else { return }
        let monitor = NWPathMonitor(); self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            let kind: String = path.usesInterfaceType(.wifi) ? "wifi" : path.usesInterfaceType(.wiredEthernet) ? "wired" : path.usesInterfaceType(.cellular) ? "cellular" : "unknown"
            let type: NWInterface.InterfaceType = kind == "wifi" ? .wifi : kind == "wired" ? .wiredEthernet : kind == "cellular" ? .cellular : .other
            let interfaces = path.availableInterfaces.filter { $0.type == type }
            let value = SceneEnvironment(available: path.status == .satisfied, kind: kind,
                interface: interfaces.count == 1 ? interfaces[0].name : "", expensive: path.isExpensive, constrained: path.isConstrained)
            Task { @MainActor in self?.receive(value) }
        }
        monitor.start(queue: DispatchQueue(label: "Ares.ScenePath"))
        manualObserver = NotificationCenter.default.addObserver(forName: .sceneManuallyApplied, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.pause(reason: "Paused after a manual scene, node or mode change") }
        }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.evaluate()
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
    }
    func receive(_ value: SceneEnvironment) {
        if environment != value { environment = value; epoch = UUID(); debounce.reset() }
    }
    func setEnabled(_ value: Bool) {
        enabled = value; defaults.set(value, forKey: "sceneAutomation.enabled")
        epoch = UUID(); debounce.reset(); lastApplied = nil
        paused = false; defaults.set(false, forKey: "sceneAutomation.paused")
        status = value ? "Waiting for a stable match" : "Automatic switching is off"
        start()
    }
    func pause(reason: String = "Paused manually") {
        guard enabled else { return }
        paused = true; defaults.set(true, forKey: "sceneAutomation.paused")
        epoch = UUID(); debounce.reset(); status = reason
    }
    func resume() {
        paused = false; defaults.set(false, forKey: "sceneAutomation.paused")
        epoch = UUID(); lastApplied = nil; debounce.reset(); status = "Waiting for a stable match"
    }
    func evaluate(now: TimeInterval = ProcessInfo.processInfo.systemUptime) async {
        guard !applying else { return }
        do {
            let scenes = try ScenarioLibrary.load(directory: ScenarioService.directory)
            let profiles = ProfileService.shared
            let result = SceneMatcher.evaluate(scenes, profile: profiles.activeProfileID, environment: environment)
            rows = result.rows
            guard enabled else { status = "Automatic switching is off"; debounce.reset(); return }
            guard !paused else { debounce.reset(); return }
            let app = AppState.shared, vm = ClashViewModel.shared
            guard !app.systemIsSleeping, !app.isPerformingNetworkOperation, !vm.isToggling,
                  vm.runtimeState.isAPIReady, vm.appliedProfileRevision == profiles.activeProfileRevision else {
                status = "Waiting for an idle, ready core"; debounce.reset(); return
            }
            let current = try ScenarioService.context()
            if let lastApplied, !ScenarioService.matches(lastApplied, defaults: .standard) {
                pause(reason: "Paused because settings or subscription changed"); return
            }
            guard let winner = result.winner, let scene = scenes.first(where: { $0.id == winner }) else {
                status = result.conflict ? "Conflicting matches at the same priority" : "No matching scene · Current configuration retained"
                debounce.reset(); return
            }
            let review = try ScenarioService.review(scene)
            guard !review.sourceChanged else { status = "Subscription changed · Review and apply the scene first"; debounce.reset(); return }
            if review.target == current.settings { status = "Matched: " + scene.name; debounce.reset(); return }
            let key = scene.id.uuidString + String(scene.updatedAt?.timeIntervalSince1970 ?? 0) + current.revision + String(describing: current.settings)
            guard debounce.ready(key: key, now: now) else { status = "Waiting for stable match: " + scene.name; return }
            let expectedEpoch = epoch
            applying = true; status = "Applying: " + scene.name
            debounce.attempted(now: now)
            let success = await ScenarioService.apply(review, automatic: true, stillValid: { [weak self] in
                guard let self else { return false }
                guard self.enabled, !self.paused, self.epoch == expectedEpoch, !AppState.shared.systemIsSleeping,
                      let latest = try? ScenarioLibrary.load(directory: ScenarioService.directory) else { return false }
                return SceneMatcher.evaluate(latest, profile: ProfileService.shared.activeProfileID, environment: self.environment).winner == scene.id
            })
            applying = false
            if success { lastApplied = try ScenarioService.context(); status = "Applied: " + scene.name }
            else { pause(reason: "Automatic switch failed · Inspect runtime and resume manually") }
        } catch {
            rows = []; debounce.reset()
            if enabled { pause(reason: "Scene data unavailable · Reload before resuming") }
            else { status = "Scene data unavailable" }
        }
    }
}
