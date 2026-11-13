import Foundation

@MainActor final class ProfileService {
    static let shared = ProfileService()
    struct Profile { let path: URL? }
    var activeProfile: Profile?
    var activeProfileRevision = "r1"
}
@MainActor final class ClashViewModel {
    static let shared = ClashViewModel()
    struct State { var isAPIReady = false }
    var runtimeState = State(), isToggling = false, appliedProfileRevision = "r1"
}
@MainActor final class ClashController {
    static let shared = ClashController()
    var runtimeGeneration = UUID()
    var proxyGroups: [ProxyGroup] = []
    var reads = 0, stale = false, fail = false
    func fetchProxiesData() async throws {
        reads += 1
        if stale { runtimeGeneration = UUID() }
        if fail { throw URLError(.cannotConnectToHost) }
    }
}
@main struct Harness {
    @MainActor static func main() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("ares-catalog-" + UUID().uuidString + ".yaml")
        defer { try? FileManager.default.removeItem(at: path) }
        try """
        proxies: [{name: Private, type: http, server: 127.0.0.1, password: secret}]
        proxy-groups:
          - {name: Select, type: select, proxies: [Private, Auto]}
          - {name: Auto, type: url-test, use: [Remote]}
          - {name: Balance, type: load-balance, proxies: [Private]}
        """.write(to: path, atomically: true, encoding: .utf8)
        ProfileService.shared.activeProfile = .init(path: path)
        let offline = try await SceneCatalogService.load()
        precondition(!offline.live && offline.groups.count == 2 && ClashController.shared.reads == 0)
        precondition(offline.groups.first(where: { $0.name == "Auto" })!.all.isEmpty)
        precondition(offline.groups.first(where: { $0.name == "Select" })!.all == ["Private", "Auto"])
        ClashViewModel.shared.runtimeState.isAPIReady = true
        ClashController.shared.proxyGroups = [.init(name: "Auto", type: "URLTest", all: ["Provider Node"]), .init(name: "Balance", type: "LoadBalance", all: ["Private"])]
        let live = try await SceneCatalogService.load()
        precondition(live.live && live.groups.count == 1 && live.groups[0].all == ["Provider Node"])
        ClashController.shared.stale = true
        do { _ = try await SceneCatalogService.load(); preconditionFailure("stale runtime accepted") } catch {}
        ClashController.shared.stale = false; ClashController.shared.fail = true
        do { _ = try await SceneCatalogService.load(); preconditionFailure("failed API concealed") } catch {}
        ClashViewModel.shared.appliedProfileRevision = "old"
        let mismatched = try await SceneCatalogService.load()
        precondition(!mismatched.live)
        print("PASS: scene catalog offline metadata, runtime provider members, non-selectable filtering, stale generation and HTTP failure")
    }
}
