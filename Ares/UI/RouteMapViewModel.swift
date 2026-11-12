import Foundation
import Combine

@MainActor final class RouteMapViewModel: ObservableObject {
    @Published private(set) var snapshot = RouteSnapshot()
    @Published private(set) var status = ""
    @Published private(set) var updated: Date?
    private let service = RouteSnapshotService()

    func monitor() async {
        while !Task.isCancelled {
            if AppState.shared.isForeground {
                let core = ClashViewModel.shared
                if core.runtimeState.isAPIReady && !core.isToggling {
                    let generation = ClashController.shared.runtimeGeneration
                    do {
                        let json = try await ClashController.shared.fetchConnections()
                        let data = try JSONSerialization.data(withJSONObject:json)
                        let decoded = ConnectionSnapshot.decode(data)
                        let resolved = await ConnectionProcessResolver.shared.resolve(decoded)
                        let input = resolved.filter { !$0.identity.isAres }.map { connection in
                            RouteSnapshot.Input(id:connection.id,application:connection.identity.name,host:connection.metadata.host,
                                destinationIP:connection.metadata.destinationIP,rule:connection.rule,chains:connection.chains,
                                upload:connection.upload,download:connection.download)
                        }
                        // Active generated config reflects applied settings, not a newly selected subscription.
                        let config = await ConfigService.shared.getConfigPath(tunEnabled:AppState.shared.tunEnabled)
                        let next = await service.snapshot(inputs:input,configURL:config,generation:generation)
                        guard !Task.isCancelled else { return }
                        if generation == ClashController.shared.runtimeGeneration && core.runtimeState.isAPIReady && !core.isToggling {
                            if next != snapshot { snapshot = next }
                            updated = Date(); status = ""
                        }
                    } catch {
                        guard !Task.isCancelled else { return }
                        status = "Connection data unavailable · showing last snapshot"
                    }
                } else {
                    snapshot = RouteSnapshot(); updated = nil; status = core.isToggling ? "Core is switching" : "Core is not running"
                }
            }
            do { try await Task.sleep(for:.seconds(1)) } catch { return }
        }
    }
}
