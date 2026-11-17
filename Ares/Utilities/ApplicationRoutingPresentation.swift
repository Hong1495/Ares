import Foundation
import SubscriptionKit

/// App grouping is for display only. Mutations and evidence keep exact paths.
nonisolated enum ApplicationRoutingPresentation {
    struct Application: Identifiable {
        let id: String
        let name: String
        let iconPath: String?
        let paths: [String]
    }

    static func applications(paths: [String]) -> [Application] {
        let grouped = Dictionary(grouping: Set(paths.filter(ApplicationRouting.validPath))) {
            ConnectionIdentity(path: $0, process: nil, source: "").key
        }
        return grouped.compactMap { id, paths in
            guard let path = paths.sorted().first else { return nil }
            let identity = ConnectionIdentity(path: path, process: nil, source: "")
            guard !identity.isAres else { return nil }
            return Application(id: id, name: identity.name, iconPath: identity.iconPath, paths: paths.sorted())
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func routeLabel(_ route: ApplicationRouting.SelectionRoute) -> String {
        switch route {
        case .inherited: "Follow rules"
        case .mixed: "Mixed"
        case .target(let target): target == "DIRECT" ? "Direct" : target == "REJECT" ? "Block" : target
        }
    }

    static func observations(_ connections: [Connection]) -> [ApplicationRouting.Observation] {
        connections.compactMap { connection in
            guard let path = connection.metadata.processPath, ApplicationRouting.validPath(path) else { return nil }
            return .init(path: path, startedAt: connection.start, rule: connection.rule,
                         payload: connection.rulePayload, chain: connection.chains)
        }
    }
}
