import Foundation
import Combine
import SubscriptionKit

@MainActor final class AppState {
    static let shared = AppState()
    var systemIsSleeping = false
    var isPerformingNetworkOperation = false
}
@MainActor final class ProfileService {
    static let shared = ProfileService()
    var activeProfileRevision = "fixture"
    var selections = 0
    func selectNode(group: ProxyGroup, node: String) async throws { selections += 1 }
    func clearNodeSelection(group: ProxyGroup) async throws { selections += 1 }
}
@MainActor enum PolicyGroupService { static var canReadRuntime = true }
@MainActor final class ClashController {
    static let shared = ClashController()
    var runtimeGeneration = UUID()
    let baseURL = "https://quality-fixture.invalid"
    var proxyGroups = [ProxyGroup(name: "Auto", type: "URLTest", now: "One", all: ["One", "Two"])]
    var reads = 0
    var invalidateAt = 0
    func fetchProxiesData() async throws { reads += 1; if reads == invalidateAt { runtimeGeneration = UUID() } }
}
final class QualityProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var requests = 0
    static let lock = NSLock()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); Self.requests += 1; let status = Self.status; Self.lock.unlock()
        let isDNS = request.url!.path.contains("dns")
        let body = isDNS ? #"{"Status":0,"TC":false,"Answer":[{"name":"fixture.","type":1,"TTL":60,"data":"192.0.2.1"}]}"# : #"{"delay":120}"#
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
@main struct Harness {
    @MainActor static func main() async {
        let suite = "ares-quality-fixture-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [QualityProtocol.self]
        let off = NetworkQualityService(defaults: defaults, session: URLSession(configuration: config))
        await off.tick(); precondition(QualityProtocol.requests == 0)
        defaults.set(true, forKey: "networkQuality.enabled"); defaults.set("Auto", forKey: "networkQuality.group")
        let service = NetworkQualityService(defaults: defaults, session: URLSession(configuration: config))
        let start = Date()
        AppState.shared.systemIsSleeping = true
        await service.tick(now: start); precondition(QualityProtocol.requests == 0)
        AppState.shared.systemIsSleeping = false; AppState.shared.isPerformingNetworkOperation = true
        await service.tick(now: start); precondition(QualityProtocol.requests == 0)
        AppState.shared.isPerformingNetworkOperation = false
        await service.tick(now: start)
        precondition(QualityProtocol.requests == 4 && service.window.samples["gstatic"]?.first?.milliseconds == 120)
        await service.tick(now: start.addingTimeInterval(10)); precondition(QualityProtocol.requests == 4)
        QualityProtocol.status = 503
        await service.tick(now: start.addingTimeInterval(60))
        precondition(service.window.samples["gstatic"]?.count == 2)
        precondition(service.window.samples["gstatic"]?.last?.milliseconds == nil)
        precondition(service.window.unavailable["dns"] == 1)
        QualityProtocol.status = 401
        await service.tick(now: start.addingTimeInterval(120))
        precondition(service.window.samples["gstatic"]?.count == 2 && service.window.unavailable["gstatic"] == 1)
        QualityProtocol.status = 200
        ClashController.shared.proxyGroups = [ProxyGroup(name: "Auto", type: "URLTest", now: "Two", all: ["One", "Two"])]
        await service.tick(now: start.addingTimeInterval(130))
        precondition(service.window.events.count == 1 && service.window.events[0].reason.contains("not exposed"))
        let before = QualityProtocol.requests
        ClashController.shared.invalidateAt = ClashController.shared.reads + 2
        await service.tick(now: start.addingTimeInterval(180))
        precondition(QualityProtocol.requests == before + 4 && service.window.samples["gstatic"]?.count == 2)
        ClashController.shared.invalidateAt = 0
        await service.tick(now: start.addingTimeInterval(190))
        precondition(service.window.samples["gstatic"]?.count == 1 && service.window.events.isEmpty)
        ClashController.shared.proxyGroups = [ProxyGroup(name: "Auto", type: "Selector", now: "Balance", all: ["Balance"]), ProxyGroup(name: "Balance", type: "LoadBalance", now: "One", all: ["One", "Two"])]
        let balancedCount = QualityProtocol.requests
        await service.tick(now: start.addingTimeInterval(240))
        precondition(QualityProtocol.requests == balancedCount && service.window.samples.isEmpty && service.status.contains("no single exit"))
        PolicyGroupService.canReadRuntime = false
        let stoppedCount = QualityProtocol.requests
        await service.tick(now: start.addingTimeInterval(250)); precondition(QualityProtocol.requests == stoppedCount)
        precondition(service.observedAt == nil && service.groups.isEmpty)
        precondition(ProfileService.shared.selections == 0, "Monitoring must never select a node")
        print("PASS: production quality service opt-in, sleep/busy/stopped gates, cadence, bounded real samples, controller-vs-probe failures, route evidence and stale generation isolation")
    }
}
