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

            var newChains: [ConnectionChain] = []

            for conn in connections {
                guard let id = conn["id"] as? String,
                      let metadata = conn["metadata"] as? [String: Any],
                      let chains = conn["chains"] as? [String],
                      let rule = conn["rule"] as? String,
                      let upload = conn["upload"] as? Int64,
                      let download = conn["download"] as? Int64 else {
                    continue
                }

                let processPath = metadata["processPath"] as? String ?? metadata["process"] as? String ?? "Unknown"
                let destinationIP = metadata["destinationIP"] as? String ?? "0.0.0.0"

                // HOSTNAME FIX:
                // Direct IP connections might have empty host. Fallback to IP.
                let rawHost = metadata["host"] as? String ?? ""
                let host = rawHost.isEmpty ? destinationIP : rawHost

                // DATA CONSISTENCY FIX:
                // Apply the same "Standard Merging" logic as TrafficAuditManager.
                // 1. If it's inside an .app, use the App Name.
                // 2. Otherwise keep original filename.
                var finalProcessName = processPath.components(separatedBy: "/").last ?? processPath

                if processPath.contains(".app") {
                    let components = processPath.split(separator: "/")
                    var currentPath = ""
                    for component in components {
                        currentPath += "/" + component
                        if component.hasSuffix(".app") {
                            // Found the App Bundle -> Use App Name
                            finalProcessName = URL(fileURLWithPath: currentPath).deletingPathExtension().lastPathComponent
                            break
                        }
                    }
                }

                // Filter out self-traffic from "Ares" (Robust check)
                if finalProcessName.localizedCaseInsensitiveContains("Ares") || finalProcessName.localizedCaseInsensitiveContains("com.herastudio.ares") {
                    continue
                }

                let chain = ConnectionChain(
                    id: id,
                    host: host,
                    sourceProcess: finalProcessName,
                    rule: rule,
                    chains: chains,
                    destinationIP: destinationIP,
                    download: download,
                    upload: upload
                )
                newChains.append(chain)
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
