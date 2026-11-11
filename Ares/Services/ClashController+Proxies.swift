import Foundation

extension ClashController {
    /// Fetch and parse proxies from Clash API
    func fetchProxiesData() async throws {
        let generation = runtimeGeneration
        // Removed noisy log: ClashService.shared.addLog("[ClashController] 📡 Fetching proxy data...")
        guard let url = URL(string: "\(baseURL)/proxies") else {
            throw NSError(domain: "ClashController", code: -10, userInfo: [NSLocalizedDescriptionKey: "Invalid Clash API URL"])
        }

        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 10))
        try CoreAPIContract.requireSuccess(response)

        // Parse in background to avoid blocking Main Actor
        let (groups, nodes) = try await Task.detached(priority: .userInitiated) {
            try ProxySnapshot.decode(data)
        }.value

        guard generation == runtimeGeneration else { throw CancellationError() }
        // Update UI state
        self.proxyGroups = groups
        self.proxyNodes = nodes
    }

    /// Select a proxy in a group
    func selectProxy(group: String, proxy: String) async throws {
        guard selectingProxyGroups.insert(group).inserted else {
            throw NSError(domain: "CoreAPI", code: -3, userInfo: [NSLocalizedDescriptionKey: "A selection is already in progress for this group"])
        }
        defer { selectingProxyGroups.remove(group) }
        ClashViewModel.shared.addLog("[ClashController] 🎯 Selecting proxy: \(proxy) in group: \(group)")

        let url = try CoreAPIContract.proxyURL(base: baseURL, name: group)

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["name": proxy]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)

        try CoreAPIContract.requireSuccess(response)
    }

    /// Test proxy delay
    func testProxyDelay(name: String, timeout: Int = 5000) async throws -> Int {
        let url = try CoreAPIContract.proxyURL(base: baseURL, name: name, delay: true, timeout: timeout)

        do {
            let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: Double(timeout) / 1000 + 2))
            try CoreAPIContract.requireSuccess(response)

            guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let delay = json["delay"] as? Int else {
                throw NSError(domain: "ClashController", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid delay response"])
            }

            // ClashService.shared.addLog("[ClashController] ✅ \(name): \(delay)ms")

            // Update node delay in memory
            await MainActor.run {
                if var node = proxyNodes[name] {
                    node.delay = delay
                    proxyNodes[name] = node
                }
            }
            return delay
        } catch {
            ClashViewModel.shared.addLog("[ClashController] ❌ Test error for \(name): \(error.localizedDescription)")
            throw error
        }
    }

    /// Fetch proxies (legacy)
    func fetchProxies() async throws -> [String: Any] {
        try await fetchProxiesData()
        return proxies
    }
}
