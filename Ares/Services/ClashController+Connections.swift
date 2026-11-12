import Foundation

extension ClashController {
    /// Fetch connections from Clash API
    func fetchConnections() async throws -> [String: Any] {
        guard let url = URL(string: "\(baseURL)/connections") else {
            throw NSError(domain: "ClashController", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 5))
        try CoreAPIContract.requireSuccess(response)
        return try CoreAPIContract.connections(data)
    }

    /// Monitor active connections and update topology data
    func monitorConnections() async {
        let generation = runtimeGeneration
        do {
            let json = try await fetchConnections()
            guard generation == runtimeGeneration, ClashViewModel.shared.isRunning, !ClashViewModel.shared.isToggling,
                  let connections = json["connections"] as? [[String: Any]] else { return }
            AppState.shared.activeConnectionsCount = connections.count

            let data = try JSONSerialization.data(withJSONObject: json)
            let resolved = await ConnectionProcessResolver.shared.resolve(ConnectionSnapshot.decode(data))
            guard generation == runtimeGeneration, ClashViewModel.shared.isRunning, !ClashViewModel.shared.isToggling else { return }
            let newChains = resolved.filter { !$0.identity.isAres }.map { connection in
                ConnectionChain(
                    id: connection.id,
                    host: connection.metadata.host.isEmpty ? connection.metadata.destinationIP : connection.metadata.host,
                    sourceProcess: connection.identity.name,
                    rule: connection.rule,
                    chains: connection.chains,
                    destinationIP: connection.metadata.destinationIP,
                    download: connection.download,
                    upload: connection.upload
                )
            }

            // Only update if changed to avoid UI flickering
            if self.activeChains != newChains {
                self.activeChains = newChains
            }

        } catch {
            guard generation == runtimeGeneration else { return }
            AppState.shared.activeConnectionsCount = ClashViewModel.shared.isRunning ? nil : 0
            ClashViewModel.shared.addLog("[ClashController] ⚠️ Failed to get connections: \(error)")
        }
    }
}
