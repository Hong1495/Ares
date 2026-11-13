import Foundation

@MainActor final class ClashViewModel {
    static let shared = ClashViewModel()
    enum Level { case debug }
    func addLog(_ message: String, level: Level? = nil) {}
}
@MainActor final class ClashController {
    var baseURL = "https://ares-config.invalid"
    var runtimeGeneration = UUID()
    var rules: [ClashRule] = []
    var rulesError: String?
    let proxySession: URLSession
    init() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FakeConfig.self]
        proxySession = URLSession(configuration: config)
    }
}
final class FakeConfig: URLProtocol, @unchecked Sendable {
    static let lock = NSLock()
    nonisolated(unsafe) private static var code = 200
    nonisolated(unsafe) private static var handler: (@Sendable () -> Void)?
    static var status: Int {
        get { lock.withLock { code } }
        set { lock.withLock { code = newValue } }
    }
    static var respond: (@Sendable () -> Void)? {
        get { lock.withLock { handler } }
        set { lock.withLock { handler = newValue } }
    }
    nonisolated(unsafe) static var payload = Data("{\"mode\":\"rule\",\"tun\":{\"enable\":false}}".utf8)
    nonisolated(unsafe) static var expectedPath = "/configs"
    nonisolated(unsafe) static var expectedMethod = "GET"
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        precondition(request.httpMethod == Self.expectedMethod)
        precondition(request.url?.path == Self.expectedPath)
        precondition(request.cachePolicy == .reloadIgnoringLocalCacheData)
        let finish: @Sendable () -> Void = { [self] in
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Self.payload)
            client?.urlProtocolDidFinishLoading(self)
        }
        Self.respond = finish
    }
    override func stopLoading() {}
}
@main struct Harness {
    @MainActor static func main() async throws {
        let controller = ClashController()
        for scenario in ["success", "http-error", "generation-changed", "endpoint-changed"] {
            FakeConfig.status = scenario == "http-error" ? 503 : 200
            FakeConfig.respond = nil
            let task = Task { try await controller.readRuntimeConfiguration() }
            // The fake transport holds the response while the simulated runtime changes.
            for _ in 0..<200 where FakeConfig.respond == nil { try await Task.sleep(for: .milliseconds(5)) }
            guard let respond = FakeConfig.respond else { fatalError("Request never reached fake transport") }
            if scenario == "generation-changed" { controller.runtimeGeneration = UUID() }
            if scenario == "endpoint-changed" { controller.baseURL = "https://new-runtime.invalid" }
            respond()
            do {
                let result = try await task.value
                precondition(scenario == "success" && !result.isEmpty)
            } catch {
                precondition(scenario != "success")
                if scenario == "http-error" { precondition((error as NSError).code == 503) }
                else { precondition(error is CancellationError) }
            }
        }
        FakeConfig.expectedPath = "/rules"
        for scenario in ["success", "http-error", "malformed", "generation-changed"] {
            FakeConfig.status = scenario == "http-error" ? 503 : 200
            FakeConfig.payload = Data((scenario == "malformed" ? "{}" : #"{"rules":[{"index":0,"type":"Match","payload":"","proxy":"DIRECT","extra":{"disabled":false,"hitCount":7}}]}"#).utf8)
            FakeConfig.respond = nil
            let task = Task { try await controller.fetchRules() }
            for _ in 0..<200 where FakeConfig.respond == nil { try await Task.sleep(for: .milliseconds(5)) }
            guard let respond = FakeConfig.respond else { fatalError("Missing rules request") }
            if scenario == "generation-changed" { controller.runtimeGeneration = UUID() }
            respond()
            do {
                try await task.value
                precondition(scenario == "success" && controller.rules.first?.hit == 7)
            } catch {
                precondition(scenario != "success")
                if scenario != "generation-changed" { precondition(controller.rules.isEmpty && controller.rulesError != nil) }
            }
        }
        let providerPayload = Data(#"{"providers":{"Asia / A?#":{"name":"Asia / A?#","behavior":"domain","vehicleType":"HTTP","ruleCount":12}}}"#.utf8)
        FakeConfig.status = 200
        FakeConfig.expectedPath = "/providers/rules"
        FakeConfig.payload = providerPayload
        FakeConfig.respond = nil
        let providersTask = Task { try await controller.fetchRuleProviders() }
        for _ in 0..<200 where FakeConfig.respond == nil { try await Task.sleep(for: .milliseconds(5)) }
        FakeConfig.respond!()
        let providers = try await providersTask.value
        precondition(providers.first?.ruleCount == 12)
        FakeConfig.respond = nil
        let updateTask = Task { try await controller.updateRuleProvider("Asia / A?#") }
        for _ in 0..<200 where FakeConfig.respond == nil { try await Task.sleep(for: .milliseconds(5)) }
        let preflight = FakeConfig.respond!
        FakeConfig.respond = nil
        preflight()
        FakeConfig.expectedMethod = "PUT"
        FakeConfig.expectedPath = "/providers/rules/Asia / A?#"
        FakeConfig.status = 503
        for _ in 0..<200 where FakeConfig.respond == nil { try await Task.sleep(for: .milliseconds(5)) }
        FakeConfig.respond!()
        do { _ = try await updateTask.value; fatalError("Update failure accepted") }
        catch { precondition((error as NSError).code == 503) }
        precondition(ResourceActivity.shared.entries.first?.outcome == .failed)
        precondition(ResourceActivity.shared.entries.first?.phase == .requesting)
        for scenario in ["success", "readback-failure", "endpoint-changed", "inline"] {
            FakeConfig.expectedMethod = "GET"; FakeConfig.expectedPath = "/providers/rules"
            FakeConfig.status = 200
            FakeConfig.payload = scenario == "inline" ? Data(#"{"providers":{"Asia / A?#":{"name":"Asia / A?#","behavior":"domain","vehicleType":"Inline","ruleCount":12}}}"#.utf8) : providerPayload
            FakeConfig.respond = nil
            let mutation = Task { try await controller.updateRuleProvider("Asia / A?#") }
            for _ in 0..<200 where FakeConfig.respond == nil { try await Task.sleep(for: .milliseconds(5)) }
            let first = FakeConfig.respond!; FakeConfig.respond = nil; first()
            if scenario != "inline" {
                FakeConfig.expectedMethod = "PUT"; FakeConfig.expectedPath = "/providers/rules/Asia / A?#"
                for _ in 0..<200 where FakeConfig.respond == nil { try await Task.sleep(for: .milliseconds(5)) }
                let put = FakeConfig.respond!; FakeConfig.respond = nil
                if scenario == "endpoint-changed" { controller.baseURL = "https://changed.invalid" }
                put()
                if scenario != "endpoint-changed" {
                    FakeConfig.expectedMethod = "GET"; FakeConfig.expectedPath = "/providers/rules"
                    FakeConfig.status = scenario == "readback-failure" ? 503 : 200
                    for _ in 0..<200 where FakeConfig.respond == nil { try await Task.sleep(for: .milliseconds(5)) }
                    let read = FakeConfig.respond!; FakeConfig.respond = nil; read()
                    if scenario == "success" {
                        FakeConfig.expectedPath = "/rules"
                        FakeConfig.payload = Data(#"{"rules":[]}"#.utf8)
                        for _ in 0..<200 where FakeConfig.respond == nil { try await Task.sleep(for: .milliseconds(5)) }
                        FakeConfig.respond!()
                    }
                }
            }
            do { _ = try await mutation.value; precondition(scenario == "success") }
            catch { precondition(scenario != "success") }
            let entry = ResourceActivity.shared.entries.first!
            if scenario == "success" { precondition(entry.outcome == .confirmed) }
            if scenario == "inline" { precondition(entry.phase == .preparing && entry.outcome == .failed) }
            if scenario == "readback-failure" { precondition(entry.phase == .reading && entry.outcome == .failed) }
            if scenario == "endpoint-changed" { precondition(entry.outcome == .cancelled) }
        }
        FakeConfig.expectedPath = "/dns/query"
        FakeConfig.expectedMethod = "GET"
        for scenario in ["success", "empty", "nxdomain", "http-error", "malformed", "generation-changed", "endpoint-changed"] {
            FakeConfig.status = scenario == "http-error" ? 503 : 200
            let body = scenario == "malformed" ? "{}" : scenario == "empty" ? #"{"Status":0,"TC":false}"# : scenario == "nxdomain" ? #"{"Status":3,"TC":false}"# : #"{"Status":0,"TC":false,"Answer":[{"name":"sample.test.","type":1,"TTL":60,"data":"192.0.2.1"}]}"#
            FakeConfig.payload = Data(body.utf8); FakeConfig.respond = nil
            let task = Task { try await controller.queryDNS(name: "sample.test", type: "A") }
            for _ in 0..<200 where FakeConfig.respond == nil { try await Task.sleep(for: .milliseconds(5)) }
            guard let respond = FakeConfig.respond else { fatalError("Missing DNS request") }
            if scenario == "generation-changed" { controller.runtimeGeneration = UUID() }
            if scenario == "endpoint-changed" { controller.baseURL = "https://dns-new.invalid" }
            respond()
            do {
                let result = try await task.value
                precondition(["success", "empty", "nxdomain"].contains(scenario))
                if scenario == "success" { precondition(result.Answer?.first?.TTL == 60 && result.Answer?.first?.typeName == "A") }
                if scenario == "empty" { precondition(result.Status == 0 && result.Answer == nil) }
                if scenario == "nxdomain" { precondition(result.statusName == "NXDOMAIN") }
            } catch {
                precondition(!["success", "empty", "nxdomain"].contains(scenario))
                if scenario.hasSuffix("changed") { precondition(error is CancellationError) }
            }
        }
        for invalid in ["", "a..test", "test?name=evil", "https://test", String(repeating: "a", count: 64) + ".test"] {
            do { _ = try DNSQueryResult.request(base: controller.baseURL, name: invalid, type: "A"); fatalError("Invalid domain accepted") }
            catch {}
        }
        let request = try DNSQueryResult.request(base: controller.baseURL, name: " _service._tcp.test. ", type: "TXT")
        precondition(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems == [URLQueryItem(name: "name", value: "_service._tcp.test."), URLQueryItem(name: "type", value: "TXT")])
        print("DNS API passed: records/TTL, NXDOMAIN vs empty, invalid input, HTTP/malformed failures, generation/endpoint races.")
        print("Rule provider API passed: metadata, encoded names and failed update propagation.")
        print("Rules API passed: real counters, malformed/HTTP failure, stale generation.")
        print("Configuration API passed: GET-only, HTTP failure, runtime generation and endpoint races.")
    }
}
