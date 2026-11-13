import Foundation

extension ClashController {
    func fetchProxyResources() async throws -> [ProxyResource] {
        try ProxyResource.decode(await proxyResourceRequest(path: "/providers/proxies"))
    }

    /// Completion means the endpoint returned and metadata was read back, not that every member is healthy.
    func performProxyResourceAction(name: String, healthCheck: Bool) async throws -> [ProxyResource] {
        guard !name.isEmpty, let escaped = name.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { throw URLError(.badURL) }
        let generation = runtimeGeneration
        let endpoint = baseURL
        let activity = ResourceActivity.shared
        let attempt = try activity.begin(name: name, kind: .nodes, action: healthCheck ? .health : .update, generation: generation, endpoint: endpoint)
        do {
            let before = try await fetchProxyResources()
            guard generation == runtimeGeneration, endpoint == baseURL else { throw CancellationError() }
            guard let resource = before.first(where: { $0.name == name }), healthCheck || resource.canUpdate else {
                throw URLError(.unsupportedURL)
            }
            let affected = Set(resource.proxies.map(\.name))
            // A long health check follows the provider's configured URL/timeout, not Ares' global test URL.
            activity.advance(attempt, to: .requesting)
            _ = try await proxyResourceRequest(path: "/providers/proxies/" + escaped + (healthCheck ? "/healthcheck" : ""),
                method: healthCheck ? "GET" : "PUT", timeout: 120)
            guard generation == runtimeGeneration, endpoint == baseURL else { throw CancellationError() }
            activity.advance(attempt, to: .reading)
            let resources = try await fetchProxyResources()
            guard generation == runtimeGeneration, endpoint == baseURL else { throw CancellationError() }
            guard let updated = resources.first(where: { $0.name == name }) else { throw URLError(.cannotParseResponse) }
            // Drop only obsolete app test values. Provider history becomes authoritative after explicit resource work.
            for member in affected.union(updated.proxies.map(\.name)) { measuredDelays.removeValue(forKey: member) }
            try await fetchProxiesData()
            guard generation == runtimeGeneration, endpoint == baseURL else { throw CancellationError() }
            activity.finish(attempt)
            return resources
        } catch {
            activity.finish(attempt, error: error)
            throw error
        }
    }

    private func proxyResourceRequest(path: String, method: String = "GET", timeout: TimeInterval = 10) async throws -> Data {
        let generation = runtimeGeneration
        let endpoint = baseURL
        guard let url = URL(string: endpoint + path) else { throw URLError(.badURL) }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = method
        let (data, response) = try await proxySession.data(for: request)
        try CoreAPIContract.requireSuccess(response)
        try Task.checkCancellation()
        guard generation == runtimeGeneration, endpoint == baseURL else { throw CancellationError() }
        return data
    }
}
