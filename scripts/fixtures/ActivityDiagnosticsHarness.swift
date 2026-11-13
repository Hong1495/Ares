import Foundation
import SubscriptionKit

@MainActor final class AppState {
    static let shared = AppState()
    var isPerformingNetworkOperation = false
}
@MainActor final class ProfileService {
    static let shared = ProfileService()
    var activeProfileRevision = "current"
}
@MainActor final class ClashViewModel {
    static let shared = ClashViewModel()
    struct State { var isAPIReady = true }
    var runtimeState = State()
    var isToggling = false
    var revision = "current"
    var configuration = "mode: rule\ntun: {enable: false}\nmixed-port: 7890\ndns: {enable: false}"
    func captureRecoveryCheckpoint() async throws -> RuntimeCheckpoint {
        RuntimeCheckpoint(configuration: configuration, profileID: nil, profileRevision: revision, selections: [:], tunEnabled: false)
    }
}
@MainActor final class ConfigService {
    static let shared = ConfigService()
    func savedConfiguration(tunEnabled: Bool) async throws -> String { ClashViewModel.shared.configuration }
}
@MainActor final class ClashController {
    static let shared = ClashController()
    var runtimeGeneration = UUID()
    var proxyGroups: [ProxyGroup] = []
    var proxyNodes: [String: ProxyNode] = [:]
    var failed = false
    var changeGeneration = false
    var mismatch = false
    func readRuntimeConfiguration() async throws -> Data {
        Data((mismatch ? #"{"mode":"rule","tun":{"enable":false},"mixed-port":9999}"# : #"{"mode":"rule","tun":{"enable":false},"mixed-port":7890}"#).utf8)
    }
    func fetchProxiesData() async throws { if failed { throw URLError(.timedOut) } }
    func fetchProxyResources() async throws -> [ProxyResource] {
        if failed { throw URLError(.timedOut) }
        return try ProxyResource.decode(Data(#"{"providers":{"Fixture":{"name":"Fixture","vehicleType":"HTTP","proxies":[{"name":"Unknown","type":"http"},{"name":"Failed","type":"http","alive":false,"history":[{"time":"2026-11-13T00:00:00Z","delay":0}]}]}}}"#.utf8))
    }
    func fetchRuleProviders() async throws -> [RuleProvider] {
        if changeGeneration { runtimeGeneration = UUID() }
        if failed { throw URLError(.timedOut) }
        return try RuleProvider.decode(Data(#"{"providers":{"Rules":{"name":"Rules","behavior":"domain","vehicleType":"HTTP","ruleCount":5}}}"#.utf8))
    }
}
@main struct Harness {
    @MainActor static func main() async throws {
        let controller = ClashController.shared
        let result = try await ActivityDiagnosticsService.load()
        precondition(result.rows.contains { $0.id == "Subscription" && $0.status == "Matches" })
        precondition(result.rows.contains { $0.id == "Nodes · Fixture" && $0.detail.contains("1 measured") && $0.detail.contains("Historical") })
        precondition(result.rows.contains { $0.id == "Rules · Rules" && $0.detail.contains("5 rules") })
        controller.mismatch = true
        ClashViewModel.shared.revision = "older"
        let mismatch = try await ActivityDiagnosticsService.load()
        precondition(mismatch.rows.contains { $0.id == "Subscription" && $0.attention })
        precondition(mismatch.rows.contains { $0.id == "Configuration · mixed-port" && $0.attention })
        controller.failed = true
        let partial = try await ActivityDiagnosticsService.load()
        precondition(partial.rows.filter { $0.status == "Unavailable" }.count == 3)
        controller.failed = false; controller.changeGeneration = true
        do { _ = try await ActivityDiagnosticsService.load(); fatalError("Stale snapshot accepted") }
        catch { precondition(error is CancellationError) }
        controller.changeGeneration = false
        ClashViewModel.shared.runtimeState.isAPIReady = false
        do { _ = try await ActivityDiagnosticsService.load(); fatalError("Stopped runtime accepted") }
        catch { precondition(error is CancellationError) }
        print("PASS: diagnostics readback/mismatch, unknown vs measured nodes, partial failures, stale generation and stopped core")
    }
}
