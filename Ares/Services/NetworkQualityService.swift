import Foundation
import Combine
import SubscriptionKit

/// Bounded session measurements. Core fallback/url-test owns failover; this observer never chooses a node automatically.
@MainActor final class NetworkQualityService: ObservableObject {
    static let shared = NetworkQualityService()
    struct Target: Identifiable, Sendable {
        let id: String
        let name: String
        let url: String
    }
    static let targets = [Target(id: "gstatic", name: "Google", url: "https://www.gstatic.com/generate_204"),
                          Target(id: "cloudflare", name: "Cloudflare", url: "https://cp.cloudflare.com/generate_204"),
                          Target(id: "github", name: "GitHub", url: "https://github.com")]
    @Published private(set) var enabled: Bool
    @Published private(set) var group: String
    @Published private(set) var interval: Int
    @Published private(set) var window = NetworkQuality.Window()
    @Published private(set) var groups: [ProxyGroup] = []
    @Published private(set) var status = "Monitoring is off"
    @Published private(set) var sampling = false
    @Published private(set) var observedAt: Date?
    @Published private(set) var error: String?
    private let defaults: UserDefaults
    private var loop: Task<Void, Never>?
    private var epoch = UUID()
    private var context = ""
    private var lastSample = Date.distantPast
    private let sessionConfiguration: URLSessionConfiguration
    private var session: URLSession
    init(defaults: UserDefaults = .standard, session: URLSession? = nil) {
        self.defaults = defaults
        enabled = defaults.bool(forKey: "networkQuality.enabled")
        group = defaults.string(forKey: "networkQuality.group") ?? ""
        let saved = defaults.integer(forKey: "networkQuality.interval")
        interval = [30, 60, 300].contains(saved) ? saved : 60
        sessionConfiguration = session?.configuration ?? .ephemeral
        self.session = session ?? URLSession(configuration: sessionConfiguration)
    }
    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                do { try await Task.sleep(for: .seconds(10)) } catch { return }
            }
        }
    }
    func setEnabled(_ value: Bool) {
        enabled = value; defaults.set(value, forKey: "networkQuality.enabled")
        reset(); status = value ? "Waiting for a ready core" : "Monitoring is off"; start()
    }
    func configure(group: String, interval: Int) {
        guard [30, 60, 300].contains(interval) else { return }
        self.group = group; self.interval = interval
        defaults.set(group, forKey: "networkQuality.group"); defaults.set(interval, forKey: "networkQuality.interval")
        reset(); start()
    }
    func reset() {
        epoch = UUID(); window = .init(); observedAt = nil; lastSample = .distantPast; context = ""; error = nil
        session.invalidateAndCancel(); session = URLSession(configuration: sessionConfiguration)
    }
    func readGroups() async {
        guard PolicyGroupService.canReadRuntime else { groups = []; return }
        let revision = ProfileService.shared.activeProfileRevision
        do {
            try await ClashController.shared.fetchProxiesData()
            guard PolicyGroupService.canReadRuntime, revision == ProfileService.shared.activeProfileRevision else { groups = []; return }
            groups = ClashController.shared.proxyGroups.filter { $0.type != "LoadBalance" }
        }
        catch { groups = []; self.error = "Runtime groups could not be read." }
    }
    private var ready: Bool {
        PolicyGroupService.canReadRuntime && !AppState.shared.systemIsSleeping && !AppState.shared.isPerformingNetworkOperation
    }
    func tick(now: Date = Date()) async {
        guard enabled else { return }
        guard ready else { status = "Paused · waiting for a ready, idle core"; groups = []; observedAt = nil; context = ""; return }
        guard !sampling else { return }
        sampling = true; defer { sampling = false }
        let controller = ClashController.shared
        let generation = controller.runtimeGeneration, revision = ProfileService.shared.activeProfileRevision, currentEpoch = epoch
        let identity = generation.uuidString + ":" + revision + ":" + group
        if context != identity { window = .init(); context = identity; lastSample = .distantPast; observedAt = nil }
        let endpoint = controller.baseURL
        func current() -> Bool { enabled && epoch == currentEpoch && generation == controller.runtimeGeneration && revision == ProfileService.shared.activeProfileRevision && ready }
        do {
            try await controller.fetchProxiesData()
            guard current() else { return }
            groups = controller.proxyGroups.filter { $0.type != "LoadBalance" }
            guard let selected = groups.first(where: { $0.name == group }), selected.now != nil else {
                status = "Choose an available policy group"; observedAt = nil; return
            }
            let path = selected.resolveCurrentPath(groups: controller.proxyGroups)
            guard !path.contains(where: { name in controller.proxyGroups.contains { $0.name == name && $0.type == "LoadBalance" } }) else {
                status = "Load-balanced route · no single exit to observe"; observedAt = nil; window = .init(); return
            }
            let automatic = path.compactMap { name in controller.proxyGroups.first { $0.name == name && $0.supportsAutomaticSelection } }.last
            window.observe(.init(path: path, pinned: automatic?.manualSelection != nil || (automatic == nil && selected.type == "Selector"), kind: automatic?.type ?? selected.type), date: now)
            observedAt = now; error = nil
            status = "Monitoring · " + (automatic.map { $0.manualSelection == nil ? "Core automatic selection" : "Manually pinned" } ?? "Manual route")
            guard now.timeIntervalSince(lastSample) >= Double(interval) else { return }
            lastSample = now
            let routeBefore = path
            let probeSession = session
            let selectedName = group
            let samples = await withTaskGroup(of: (String, NetworkQuality.Sample?).self, returning: [(String, NetworkQuality.Sample?)].self) { tasks in
                for target in Self.targets {
                    tasks.addTask { await Self.probe(session: probeSession, endpoint: endpoint, group: selectedName, target: target) }
                }
                tasks.addTask { await Self.dns(session: probeSession, endpoint: endpoint) }
                var values: [(String, NetworkQuality.Sample?)] = []
                for await value in tasks { values.append(value) }
                return values
            }
            guard current() else { return }
            try await controller.fetchProxiesData()
            guard current(), let after = controller.proxyGroups.first(where: { $0.name == selectedName }), routeBefore == after.resolveCurrentPath(groups: controller.proxyGroups) else {
                status = "Route changed during probes · batch discarded"; return
            }
            for (name, sample) in samples { if let sample { window.record(sample, target: name) } else { window.recordUnavailable(target: name) } }
        } catch {
            guard current() else { return }
            status = "Controller unavailable · no connectivity result inferred"; observedAt = nil
        }
    }
    // /delay asks the selected outbound to perform a real HTTPS request; its reported duration is not ICMP RTT.
    nonisolated private static func probe(session: URLSession, endpoint: String, group: String, target: Target) async -> (String, NetworkQuality.Sample?) {
        do {
            let base = try CoreAPIContract.proxyURL(base: endpoint, name: group, delay: true, timeout: 5000)
            var url = URLComponents(url: base, resolvingAgainstBaseURL: false)!
            url.queryItems = [URLQueryItem(name: "timeout", value: "5000"), URLQueryItem(name: "url", value: target.url)]
            let (data, response) = try await session.data(for: URLRequest(url: url.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 7))
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200...299).contains(status), let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let delay = json["delay"] as? Int, delay > 0 {
                return (target.id, .init(milliseconds: delay, outcome: "HTTPS probe succeeded"))
            }
            // mihomo returns 503/504 when URLTest cannot reach a target. Other errors are controller errors, not path failures.
            if status == 503 || status == 504 { return (target.id, .init(milliseconds: nil, outcome: "Core probe failed (\(status))")) }
            return (target.id, nil)
        } catch { return (target.id, nil) }
    }
    nonisolated private static func dns(session: URLSession, endpoint: String) async -> (String, NetworkQuality.Sample?) {
        do {
            let start = ContinuousClock.now
            let request = try DNSQueryResult.request(base: endpoint, name: "www.gstatic.com", type: "A")
            let (data, response) = try await session.data(for: request)
            try CoreAPIContract.requireSuccess(response)
            let result = try JSONDecoder().decode(DNSQueryResult.self, from: data)
            let duration = start.duration(to: .now).components
            let success = result.Status == 0 && !(result.Answer ?? []).isEmpty
            return ("dns", .init(milliseconds: success ? Int(duration.seconds * 1000 + duration.attoseconds / 1_000_000_000_000_000) : nil,
                                  outcome: success ? "Resolver API response · cache may apply" : result.statusName))
        } catch { return ("dns", nil) }
    }
    func select(member: String) async {
        guard ready, let selected = groups.first(where: { $0.name == group }) else { return }
        do { try await ProfileService.shared.selectNode(group: selected, node: member); await tick() }
        catch { self.error = "Selection was not confirmed. Refresh and try again." }
    }
    func resumeAutomatic(group name: String) async {
        guard ready, let selected = ClashController.shared.proxyGroups.first(where: { $0.name == name && $0.supportsAutomaticSelection }) else { return }
        do { try await ProfileService.shared.clearNodeSelection(group: selected); await tick() }
        catch { self.error = "Automatic selection could not be confirmed." }
    }
}
