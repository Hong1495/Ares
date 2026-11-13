import SwiftUI
import SubscriptionKit

@MainActor final class ClashController: ObservableObject {
    @Published var rules: [ClashRule] = (0..<55).map { index in
        ClashRule(index: index, type: index % 2 == 0 ? "RuleSet" : "DomainSuffix",
            payload: index % 2 == 0 ? "Streaming" : "example.test", proxy: "Proxy",
            extra: index % 3 == 0 ? nil : .init(disabled: false, hitCount: UInt64(index * 123)))
    }
    @Published var rulesError: String?
    @Published var runtimeGeneration = UUID()
    func fetchRules() async throws {}
    func fetchRuleProviders() async throws -> [RuleProvider] {
        [.init(name: "Streaming", behavior: "domain", vehicleType: "HTTP", ruleCount: 12345, updatedAt: "2026-11-13T10:00:00+08:00"),
         .init(name: "Local", behavior: "classical", vehicleType: "Inline", ruleCount: 3, updatedAt: nil)]
    }
    func updateRuleProvider(_ name: String) async throws -> [RuleProvider] { try await fetchRuleProviders() }
}
@MainActor final class AppState {
    static let shared = AppState()
    var lastOperationError: String?
    func beginOperation(_ text: String) -> Bool { true }
    func finishOperation(error: String?) {}
}
@MainActor final class ProfileService {
    static let shared = ProfileService()
    var activeProfileRevision = "preview"
}
@MainActor enum LocalRulesService {
    static func apply(_ text: String, expectedRevision: String, expectedRules: String? = nil) async -> Bool { false }
}
@MainActor enum RuleSourceService {
    static func load() async throws -> RuleSourceDocument.Document {
        try RuleSourceDocument.read(configuration: "rules: ['RULE-SET,Streaming,Proxy', 'MATCH,DIRECT']", subscription: "rules: ['MATCH,DIRECT']", localRules: "RULE-SET,Streaming,Proxy")
    }
}
// Shadow persistence: this preview cannot read or write the user's preferences.
final class UserDefaults {
    static let standard = UserDefaults()
    func string(forKey: String) -> String? { "DOMAIN-SUFFIX,example.test,DIRECT" }
}
@main struct RulesPreview: App {
    @StateObject private var controller = ClashController()
    var body: some Scene {
        WindowGroup("Ares Rules Preview") {
            RulesView().environmentObject(controller).frame(minWidth: 850, minHeight: 540)
        }.defaultSize(width: 1000, height: 640)
    }
}
