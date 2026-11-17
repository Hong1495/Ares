import Foundation
import Combine
import SubscriptionKit

@MainActor enum ApplicationRoutingService {
    struct Snapshot { let rules: String; let targets: [String] }
    struct Undo { let previous: String; let applied: String }
    static var verificationSince: [String: Date] = [:]
    static var rules = ""
    static var rows: [Connection] = []
    static var failNextApply = false
    static func load() async throws -> Snapshot { .init(rules: rules, targets: ["DIRECT", "REJECT", "Auto"]) }
    static func connections() async throws -> [Connection] { rows }
    static func apply(paths: [String], target: String?, snapshot: Snapshot) async throws -> Undo? {
        if failNextApply { failNextApply = false; throw URLError(.cannotConnectToHost) }
        guard rules == snapshot.rules else { throw URLError(.cancelled) }
        let previous = rules
        rules = try ApplicationRouting.replacing(rules, paths: paths, target: target)
        for path in paths { verificationSince[path] = Date() }
        return .init(previous: previous, applied: rules)
    }
    static func undo(_ undo: Undo) async -> Bool {
        guard rules == undo.applied else { return false }
        rules = undo.previous
        for path in ApplicationRouting.paths(in: rules) { verificationSince[path] = Date() }
        return true
    }
}

@main struct ApplicationRoutingHarness {
    @MainActor static func main() async {
        let main = "/Applications/Browser.app/Contents/MacOS/Browser"
        let helper = "/Applications/Browser.app/Contents/Helpers/Network.app/Contents/MacOS/Network"
        let other = "/Applications/Other.app/Contents/MacOS/Other"
        func connection(_ path: String, target: String = "Auto", start: Date = Date()) -> Connection {
            .init(id: path, metadata: .init(network: "tcp", type: "HTTP", sourceIP: "127.0.0.1", destinationIP: "192.0.2.10", sourcePort: "5000", destinationPort: "443", host: "example.test", processPath: path), upload: 0, download: 0, start: start, chains: [target], rule: "ProcessPath", rulePayload: path)
        }
        ApplicationRoutingService.rules = "PROCESS-PATH,\(main),Auto"
        ApplicationRoutingService.rows = [connection(main), connection(helper), connection(other)]
        let model = ApplicationRoutingViewModel()
        await model.start(paths: [])
        precondition(model.applications.count == 1 && model.discovered.count == 2)
        let app = model.applications[0]
        precondition(app.name == "Browser" && Set(app.paths) == [main, helper])
        model.select(app.id)
        precondition(model.target == .mixed && model.selectedPaths == [main, helper] && !model.canApply)
        model.setPath(helper, included: false)
        precondition(model.target == .target("Auto") && model.selectedPaths == [main])
        precondition(model.verification(paths: app.paths, ruleMode: true) == .partial)
        model.target = .target("REJECT")
        await model.reload()
        precondition(model.target == .target("REJECT"), "Unrelated refresh must not discard an unsaved target")
        model.setPath(helper, included: true)
        precondition(model.target == .mixed)
        model.target = .target("DIRECT")
        precondition(model.canApply)
        await model.apply()
        precondition(model.error == nil && model.undo != nil && !model.canApply)
        precondition(model.route(paths: app.paths) == .target("DIRECT"))
        precondition(model.verification(paths: app.paths, ruleMode: true) == .pending, "Old connections cannot verify a new rule")
        ApplicationRoutingService.rows = [connection(main, target: "DIRECT"), connection(helper, target: "DIRECT")]
        await model.readConnections()
        precondition(model.verification(paths: app.paths, ruleMode: true) == .verified)
        await model.revert()
        precondition(model.undo == nil && model.route(paths: [main]) == .target("Auto") && model.route(paths: [helper]) == .inherited)
        model.setPath(helper, included: false)
        model.target = .inherited
        await model.apply()
        precondition(ApplicationRoutingService.rules.isEmpty && model.route(paths: [main]) == .inherited)
        // Failure leaves both saved state and the user's previous undo intact.
        model.target = .target("REJECT")
        ApplicationRoutingService.failNextApply = true
        await model.apply()
        precondition(model.error != nil && ApplicationRoutingService.rules.isEmpty && !model.busy)
        ApplicationRoutingService.rules = "PROCESS-PATH,\(other),DIRECT"
        await model.revert()
        precondition(model.error != nil && ApplicationRoutingService.rules.contains(other))
        model.add(paths: [other])
        precondition(model.selectedApplication?.name == "Other")
        precondition(model.target == .target("DIRECT"))
        precondition(model.selectedPaths == [other])
        model.invalidateRuntime()
        precondition(model.capturedAt == nil && model.connections.isEmpty)
        let context = ApplicationRoutingViewModel()
        await context.start(paths: [main, other])
        precondition(context.selectedPaths.count == 1, "Opening several app paths must not edit another app invisibly")
        print("PASS: application grouping, exact helper selection, saved-route readback, draft preservation, apply/new-connection verification, inheritance, undo and stale/failure handling")
    }
}
