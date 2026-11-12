import Foundation

extension ClashController {
    /// Fetch and parse proxies from Clash API
    func fetchProxiesData() async throws {
        let generation = runtimeGeneration
        // Removed noisy log: ClashService.shared.addLog("[ClashController] 📡 Fetching proxy data...")
        guard let url = URL(string: "\(baseURL)/proxies") else {
            throw NSError(domain: "ClashController", code: -10, userInfo: [NSLocalizedDescriptionKey: "Invalid Clash API URL"])
        }

        let (data, response) = try await proxySession.data(for: URLRequest(url: url, timeoutInterval: 10))
        try CoreAPIContract.requireSuccess(response)

        // Parse in background to avoid blocking Main Actor
        let (groups, nodes) = try await Task.detached(priority: .userInitiated) {
            try ProxySnapshot.decode(data)
        }.value

        try Task.checkCancellation()
        guard generation == runtimeGeneration else { throw CancellationError() }
        // Update UI state
        self.proxyGroups = groups
        self.proxyNodes = nodes.mapValues { node in
            var result = node
            if let delay = measuredDelays[node.name] { result.delay = delay }
            return result
        }
    }

    /// Select a proxy in a group
    func selectProxy(group: String, proxy: String) async throws {
        guard selectingProxyGroups.insert(group).inserted else {
            throw NSError(domain: "CoreAPI", code: -3, userInfo: [NSLocalizedDescriptionKey: "A selection is already in progress for this group"])
        }
        defer { selectingProxyGroups.remove(group) }
        ClashViewModel.shared.addLog("[ClashController] 🎯 Selecting proxy: \(proxy) in group: \(group)")

        let generation = runtimeGeneration
        let url = try CoreAPIContract.proxyURL(base: baseURL, name: group)

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["name": proxy]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await proxySession.data(for: request)

        try CoreAPIContract.requireSuccess(response)
        guard generation == runtimeGeneration else { throw CancellationError() }
        try await fetchProxiesData()
        guard generation == runtimeGeneration,
              let selectedGroup = proxyGroups.first(where: { $0.name == group }),
              selectedGroup.confirmsSelection(proxy) else {
            throw NSError(domain: "Selection", code: 3, userInfo: [NSLocalizedDescriptionKey: "The core did not confirm the selected node."])
        }
    }

    func clearProxySelection(group: String) async throws {
        let generation = runtimeGeneration
        let url = try CoreAPIContract.proxyURL(base: baseURL, name: group)
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "DELETE"
        let (_, response) = try await proxySession.data(for: request)
        try CoreAPIContract.requireSuccess(response)
        guard generation == runtimeGeneration else { throw CancellationError() }
        try await fetchProxiesData()
        guard generation == runtimeGeneration,
              let resetGroup = proxyGroups.first(where: { $0.name == group }),
              resetGroup.supportsAutomaticSelection, resetGroup.manualSelection == nil else {
            throw NSError(domain: "Selection", code: 5, userInfo: [NSLocalizedDescriptionKey: "The core did not confirm automatic node selection."])
        }
    }

    /// Test proxy delay
    func testProxyDelay(name: String, timeout: Int = 5000) async throws -> Int {
        try Task.checkCancellation()
        guard testingProxyNames.insert(name).inserted else { throw CancellationError() }
        defer { testingProxyNames.remove(name) }
        let generation = runtimeGeneration
        let url = try CoreAPIContract.proxyURL(base: baseURL, name: name, delay: true, timeout: timeout)

        do {
            let (data, response) = try await proxySession.data(for: URLRequest(url: url, timeoutInterval: Double(timeout) / 1000 + 2))
            try CoreAPIContract.requireSuccess(response)

            guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let delay = json["delay"] as? Int, delay > 0 else {
                throw NSError(domain: "ClashController", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid delay response"])
            }

            // ClashService.shared.addLog("[ClashController] ✅ \(name): \(delay)ms")

            // Update node delay in memory
            try Task.checkCancellation()
            guard generation == runtimeGeneration else { throw CancellationError() }
            measuredDelays[name] = delay
            if var node = proxyNodes[name] {
                node.delay = delay
                proxyNodes[name] = node
            }
            return delay
        } catch {
            guard generation == runtimeGeneration, !Task.isCancelled,
                  !(error is CancellationError), (error as? URLError)?.code != .cancelled else {
                throw CancellationError()
            }
            measuredDelays[name] = 0
            if var node = proxyNodes[name] {
                node.delay = 0
                proxyNodes[name] = node
            }
            ClashViewModel.shared.addLog("[ClashController] ❌ Test error for \(name): \(error.localizedDescription)")
            throw error
        }
    }

    /// Shared automatic/manual batch. Six requests at a time, once per name even
    /// when the same node appears in several groups. Never starts a core.
    func testAllProxyDelays() async {
        guard !isTestingAllProxies else { return }
        isTestingAllProxies = true
        defer { isTestingAllProxies = false }
        let generation = runtimeGeneration
        let builtIns: Set<String> = ["Direct", "Reject", "RejectDrop", "Pass", "Compatible", "PassRule"]
        let groupNames = Set(proxyGroups.map(\.name))
        let names = proxyNodes.values.filter { !builtIns.contains($0.type) && !groupNames.contains($0.name) }.map(\.name).sorted()
        await withTaskGroup(of: Void.self) { tasks in
            var next = 0
            for _ in 0..<min(6, names.count) {
                let name = names[next]
                next += 1
                tasks.addTask { _ = try? await self.testProxyDelay(name: name) }
            }
            while await tasks.next() != nil {
                guard !Task.isCancelled, generation == runtimeGeneration else {
                    tasks.cancelAll()
                    break
                }
                if next < names.count {
                    let name = names[next]
                    next += 1
                    tasks.addTask { _ = try? await self.testProxyDelay(name: name) }
                }
            }
        }
    }

    func startAutomaticLatencyTesting() {
        guard automaticLatencyTask == nil else { return }
        automaticLatencyTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    try await self.fetchProxiesData()
                    try Task.checkCancellation()
                    await self.testAllProxyDelays()
                    try await Task.sleep(for: .seconds(300))
                } catch {
                    if Task.isCancelled { return }
                    // Retry a temporarily unavailable controller without a busy loop.
                    do { try await Task.sleep(for: .seconds(15)) } catch { return }
                }
            }
        }
    }

    /// Fetch proxies (legacy)
    func fetchProxies() async throws -> [String: Any] {
        try await fetchProxiesData()
        return proxies
    }
}
