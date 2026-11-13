import Foundation
import Combine

// Only the proxy API extension is production code in this executable. No app,
// lifecycle observer, core launcher, privileges, or system proxy code is linked.
@MainActor final class ClashViewModel {
    static let shared = ClashViewModel()
    func addLog(_ message: String) {}
}
@MainActor final class ClashController {
    let baseURL = "https://ares-tests.invalid"
    var runtimeGeneration = UUID() { didSet { measuredDelays.removeAll() } }
    var selectingProxyGroups: Set<String> = []
    var testingProxyNames: Set<String> = []
    var measuredDelays: [String: Int] = [:]
    var isTestingAllProxies = false
    var automaticLatencyTask: Task<Void, Never>?
    var proxyGroups: [ProxyGroup] = []
    var proxyNodes: [String: ProxyNode] = [:]
    var proxies: [String: Any] = [:]
    let proxySession: URLSession
    init() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FakeCore.self]
        proxySession = URLSession(configuration: config)
    }
}
final class FakeCore: URLProtocol, @unchecked Sendable {
    static let lock = NSLock()
    nonisolated(unsafe) static var groups: [String: [String: Any]] = [
        "Select": ["type": "Selector", "all": ["Auto", "B"], "now": "B"],
        "Auto": ["type": "URLTest", "all": ["A", "B"], "now": "A", "fixed": ""],
        "Fallback": ["type": "Fallback", "all": ["A", "B"], "now": "A", "fixed": ""]
    ]
    nonisolated(unsafe) static var resourceStatus = 200
    nonisolated(unsafe) static var failResourceReadback = false
    nonisolated(unsafe) static var mutationSeen = false
    nonisolated(unsafe) static var resourceDelay = 0.0
    nonisolated(unsafe) static var resourceMethods: [String] = []
    nonisolated(unsafe) static var active = 0, peak = 0, requests = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let path = request.url!.pathComponents
        let name = path.count > 2 ? path[2] : ""
        let isDelay = path.last == "delay"
        var status = 200
        var body: [String: Any] = [:]
        if path.count > 1 && path[1] == "providers" {
            Self.resourceMethods.append(request.httpMethod! + " " + request.url!.path)
            if path.count == 3 {
                if Self.failResourceReadback && Self.mutationSeen { status = 503 }
                body = ["providers": ["Remote / A?#": ["name": "Remote / A?#", "vehicleType": "HTTP", "proxies": [["name": "Failed", "type": "VLESS"]]]]]
            } else { Self.mutationSeen = true; status = Self.resourceStatus }
        } else if isDelay {
            Self.active += 1
            Self.peak = max(Self.peak, Self.active)
            Self.requests += 1
            status = name == "Failed" ? 503 : 200
            body = ["delay": 120]
        } else if request.httpMethod == "PUT" {
            var payload = request.httpBody ?? Data()
            if let stream = request.httpBodyStream {
                stream.open()
                var buffer = [UInt8](repeating: 0, count: 1024)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    payload.append(contentsOf: buffer.prefix(count))
                }
                stream.close()
            }
            let json = try! JSONSerialization.jsonObject(with: payload) as! [String: String]
            if Self.groups[name]?["type"] as? String == "Selector" {
                Self.groups[name]?["now"] = json["name"]
            } else {
                // Intent and current route deliberately differ for auto groups.
                Self.groups[name]?["fixed"] = json["name"]
            }
            status = 204
        } else if request.httpMethod == "DELETE" {
            Self.groups[name]?["fixed"] = ""
            status = 204
        } else {
            body = ["proxies": Self.groups.merging(["Failed": ["type": "VLESS", "history": [["delay": 30]]]]) { a, _ in a }]
        }
        let responseDelay = path.count > 1 && path[1] == "providers" ? Self.resourceDelay : (isDelay ? 0.06 : 0)
        Self.lock.unlock()
        let data = try! JSONSerialization.data(withJSONObject: body)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        DispatchQueue.global().asyncAfter(deadline: .now() + responseDelay) { [self] in
            if isDelay { Self.lock.lock(); Self.active -= 1; Self.lock.unlock() }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}
@main struct ProxyControllerHarness {
    @MainActor static func main() async throws {
        let controller = ClashController()
        let resources = try await controller.fetchProxyResources()
        precondition(resources.first?.name == "Remote / A?#")
        controller.measuredDelays["Failed"] = 999
        _ = try await controller.performProxyResourceAction(name: "Remote / A?#", healthCheck: false)
        precondition(controller.measuredDelays["Failed"] == nil)
        _ = try await controller.performProxyResourceAction(name: "Remote / A?#", healthCheck: true)
        precondition(FakeCore.resourceMethods.contains("PUT /providers/proxies/Remote / A?#"))
        precondition(FakeCore.resourceMethods.contains("GET /providers/proxies/Remote / A?#/healthcheck"))
        precondition(ResourceActivity.shared.entries.first?.outcome == .confirmed)
        FakeCore.failResourceReadback = true; FakeCore.mutationSeen = false
        do { _ = try await controller.performProxyResourceAction(name: "Remote / A?#", healthCheck: false); fatalError("Readback failure accepted") }
        catch { precondition((error as NSError).code == 503) }
        precondition(ResourceActivity.shared.entries.first?.phase == .reading && ResourceActivity.shared.entries.first?.outcome == .failed)
        FakeCore.failResourceReadback = false
        FakeCore.resourceStatus = 503
        do { _ = try await controller.performProxyResourceAction(name: "Remote / A?#", healthCheck: false); fatalError("Resource failure accepted") }
        catch { precondition((error as NSError).code == 503) }
        FakeCore.resourceStatus = 200
        FakeCore.resourceDelay = 0.1
        let staleResource = Task { try await controller.fetchProxyResources() }
        try await Task.sleep(for: .milliseconds(30))
        controller.runtimeGeneration = UUID()
        do { _ = try await staleResource.value; fatalError("Stale resources accepted") }
        catch { precondition(error is CancellationError) }
        let staleAction = Task { try await controller.performProxyResourceAction(name: "Remote / A?#", healthCheck: false) }
        try await Task.sleep(for: .milliseconds(30))
        do { _ = try await controller.performProxyResourceAction(name: "Remote / A?#", healthCheck: true); fatalError("Concurrent resource action accepted") }
        catch { precondition((error as NSError).code == NSURLErrorResourceUnavailable) }
        controller.runtimeGeneration = UUID()
        do { _ = try await staleAction.value; fatalError("Stale action accepted") }
        catch { precondition(error is CancellationError) }
        precondition(ResourceActivity.shared.entries.first?.outcome == .cancelled)
        FakeCore.resourceDelay = 0
        print("PASS: stale resource response rejected after runtime change")
        print("PASS: resource methods, encoded names, update/health readback, stale latency invalidation and HTTP failure")
        try await controller.fetchProxiesData()
        try await controller.selectProxy(group: "Select", proxy: "Auto")
        precondition(controller.proxyGroups.first { $0.name == "Select" }!.now == "Auto")
        for group in ["Auto", "Fallback"] {
            try await controller.selectProxy(group: group, proxy: "B")
            precondition(controller.proxyGroups.first { $0.name == group }!.fixed == "B")
            try await controller.clearProxySelection(group: group)
            precondition(controller.proxyGroups.first { $0.name == group }!.manualSelection == nil)
        }
        do { _ = try await controller.testProxyDelay(name: "Failed"); fatalError("503 must fail") } catch {}
        precondition(controller.proxyNodes["Failed"]!.delay == 0)
        try await controller.fetchProxiesData()
        precondition(controller.proxyNodes["Failed"]!.delay == 0, "Polling must not resurrect old green latency")
        controller.proxyNodes = Dictionary(uniqueKeysWithValues: (0..<18).map { ("Node\($0)", ProxyNode(name: "Node\($0)", type: "VLESS")) })
        await controller.testAllProxyDelays()
        precondition(controller.proxyNodes.values.allSatisfy { $0.delay == 120 })
        precondition(FakeCore.peak <= 6 && FakeCore.peak > 1)
        let first = Task { try await controller.testProxyDelay(name: "Node0") }
        try await Task.sleep(for: .milliseconds(10))
        do { _ = try await controller.testProxyDelay(name: "Node0"); fatalError("duplicate request accepted") } catch {}
        _ = try await first.value
        let stale = Task { try await controller.testProxyDelay(name: "Node0") }
        try await Task.sleep(for: .milliseconds(10))
        controller.runtimeGeneration = UUID()
        controller.proxyNodes["Node0"]?.delay = 77
        do { _ = try await stale.value; fatalError("stale result accepted") } catch {}
        precondition(controller.proxyNodes["Node0"]?.delay == 77)
        precondition(controller.testingProxyNames.isEmpty)
        print("PASS: nested selector, URLTest/Fallback fixed readback and automatic reset, failed latency persistence, six-request batch bound, deduplication, stale runtime protection")
    }
}
