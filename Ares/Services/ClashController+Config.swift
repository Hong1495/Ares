import Foundation

extension ClashController {
    /// One-shot read; never starts or mutates the core. Reject responses from an old runtime.
    func readRuntimeConfiguration() async throws -> Data {
        let generation = runtimeGeneration
        let endpoint = baseURL
        guard let url = URL(string: "\(endpoint)/configs") else { throw URLError(.badURL) }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
        request.httpMethod = "GET"
        let (data, response) = try await proxySession.data(for: request)
        try CoreAPIContract.requireSuccess(response)
        try Task.checkCancellation()
        guard generation == runtimeGeneration, endpoint == baseURL else { throw CancellationError() }
        return data
    }

    /// Set Clash mode (rule/global/direct)
    func setMode(_ mode: ClashConfig.Mode) async throws {
        guard let url = URL(string: "\(baseURL)/configs") else {
            throw NSError(domain: "ClashController", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid Clash API URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["mode": mode.rawValue]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let generation = runtimeGeneration
        let (_, response) = try await proxySession.data(for: request)
        try validateMutationResponse(response)
        guard generation == runtimeGeneration else { throw CancellationError() }

        ClashViewModel.shared.addLog("[ClashController] Set mode to \(mode.rawValue)", level: .debug)
    }

    /// Get current Clash mode
    func getCurrentMode() async throws -> ClashConfig.Mode {
        let data = try await readRuntimeConfiguration()
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        if let modeString = json?["mode"] as? String,
           let mode = ClashConfig.Mode(rawValue: modeString) {
            return mode
        }

        throw NSError(domain: "ClashController", code: 2, userInfo: nil)
    }

    /// Set Clash log level
    func setLogLevel(_ level: String) async throws {
        guard let url = URL(string: "\(baseURL)/configs") else {
            throw NSError(domain: "ClashController", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid Clash API URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["log-level": level]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let generation = runtimeGeneration
        let (_, response) = try await proxySession.data(for: request)
        try validateMutationResponse(response)
        guard generation == runtimeGeneration else { throw CancellationError() }
        let data = try await readRuntimeConfiguration()
        guard let values = try JSONSerialization.jsonObject(with: data) as? [String: Any], values["log-level"] as? String == level else {
            throw URLError(.cannotParseResponse)
        }
        ClashViewModel.shared.addLog("[ClashController] Set log level to \(level)")
    }

    private func validateMutationResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw NSError(
                domain: "ClashController",
                code: status,
                userInfo: [NSLocalizedDescriptionKey: "Clash API rejected the requested change (HTTP \(status))"]
            )
        }
    }

    /// Preserve core evaluation order, actual counters and runtime identity.
    func fetchRules() async throws {
        let generation = runtimeGeneration
        let endpoint = baseURL
        do {
            let data = try await readRuleResource(path: "/rules")
            rules = try ClashRule.decode(data)
            rulesError = nil
        } catch {
            guard generation == runtimeGeneration, endpoint == baseURL else { throw error }
            rules = []
            rulesError = "Rules could not be read from the current core."
            throw error
        }
    }

    func fetchRuleProviders() async throws -> [RuleProvider] {
        try RuleProvider.decode(await readRuleResource(path: "/providers/rules"))
    }

    func updateRuleProvider(_ name: String) async throws -> [RuleProvider] {
        guard let escaped = name.addingPercentEncoding(withAllowedCharacters: .alphanumerics), !name.isEmpty else {
            throw URLError(.badURL)
        }
        let generation = runtimeGeneration, endpoint = baseURL
        let activity = ResourceActivity.shared
        let attempt = try activity.begin(name: name, kind: .rules, action: .update, generation: generation, endpoint: endpoint)
        do {
            let before = try await fetchRuleProviders()
            guard generation == runtimeGeneration, endpoint == baseURL else { throw CancellationError() }
            guard before.first(where: { $0.name == name })?.canUpdate == true else { throw URLError(.unsupportedURL) }
            activity.advance(attempt, to: .requesting)
            _ = try await readRuleResource(path: "/providers/rules/" + escaped, method: "PUT")
            activity.advance(attempt, to: .reading)
            let providers = try await fetchRuleProviders()
            guard generation == runtimeGeneration, endpoint == baseURL, providers.contains(where: { $0.name == name }) else {
                throw CancellationError()
            }
            try await fetchRules()
            guard generation == runtimeGeneration, endpoint == baseURL else { throw CancellationError() }
            activity.finish(attempt)
            return providers
        } catch {
            activity.finish(attempt, error: error)
            throw error
        }
    }

    private func readRuleResource(path: String, method: String = "GET") async throws -> Data {
        let generation = runtimeGeneration
        let endpoint = baseURL
        guard let url = URL(string: endpoint + path) else { throw URLError(.badURL) }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: method == "GET" ? 5 : 30)
        request.httpMethod = method
        let (data, response) = try await proxySession.data(for: request)
        try CoreAPIContract.requireSuccess(response)
        try Task.checkCancellation()
        guard generation == runtimeGeneration, endpoint == baseURL else { throw CancellationError() }
        return data
    }
}
