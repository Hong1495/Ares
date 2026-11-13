import Foundation
import SubscriptionKit

@MainActor enum RuleSourceService {
    static func load() async throws -> RuleSourceDocument.Document {
        let vm = ClashViewModel.shared
        let controller = ClashController.shared
        let generation = controller.runtimeGeneration
        let checkpoint = try vm.recoveryCheckpoint()
        let revision = ProfileService.shared.activeProfileRevision
        let sameSource = checkpoint.profileRevision == revision && checkpoint.profileID == ProfileService.shared.activeProfileID
        let path = sameSource ? ProfileService.shared.activeProfile?.path : nil
        let local = sameSource ? UserDefaults.standard.string(forKey: DefaultsKeys.localRules) ?? "" : nil
        let result = try await ConfigService.shared.ruleSources(configuration: checkpoint.configuration,
            profilePath: path, localRules: local)
        guard generation == controller.runtimeGeneration, vm.runtimeState.isAPIReady,
              revision == ProfileService.shared.activeProfileRevision,
              !sameSource || local == (UserDefaults.standard.string(forKey: DefaultsKeys.localRules) ?? "") else {
            throw CancellationError()
        }
        return result
    }
}
