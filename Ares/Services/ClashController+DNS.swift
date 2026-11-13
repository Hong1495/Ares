import Foundation

extension ClashController {
    func queryDNS(name: String, type: String) async throws -> DNSQueryResult {
        let generation = runtimeGeneration, endpoint = baseURL
        let request = try DNSQueryResult.request(base: endpoint, name: name, type: type)
        let (data, response) = try await proxySession.data(for: request)
        try CoreAPIContract.requireSuccess(response)
        try Task.checkCancellation()
        guard generation == runtimeGeneration, endpoint == baseURL else { throw CancellationError() }
        return try JSONDecoder().decode(DNSQueryResult.self, from: data)
    }
}
