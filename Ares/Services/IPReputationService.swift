import Foundation
import Combine

@MainActor
final class IPReputationService: ObservableObject {
    static let shared = IPReputationService()
    @Published private(set) var result: IPReputation?
    @Published private(set) var checking = false
    @Published private(set) var unavailable = false
    private var cache: [String: IPReputation] = [:]
    private var nextAttempt: [String: Date] = [:]
    private var generation = UUID()
    private let lifetime: TimeInterval = 6 * 60 * 60

    func clear() {
        generation = UUID()
        result = nil
        checking = false
        unavailable = false
    }

    func monitor(ip: String, enabled: Bool) async {
        clear()
        guard enabled, ExitIdentity.isAddress(ip) else { return }
        let token = generation
        while !Task.isCancelled && token == generation {
            let now = Date()
            if let saved = cache[ip], now.timeIntervalSince(saved.checkedAt) < lifetime {
                result = saved
            } else if now >= (nextAttempt[ip] ?? .distantPast) {
                result = nil
                checking = true
                let fetched = await fetch(ip: ip)
                guard !Task.isCancelled, token == generation else { return }
                checking = false
                unavailable = fetched == nil
                result = fetched
                if let fetched {
                    cache = cache.filter { now.timeIntervalSince($0.value.checkedAt) < lifetime }
                    cache[ip] = fetched
                    nextAttempt[ip] = now.addingTimeInterval(lifetime)
                } else {
                    // Includes provider quotas; never hammer an unavailable service.
                    nextAttempt[ip] = now.addingTimeInterval(30 * 60)
                }
            } else {
                unavailable = true
            }
            do { try await Task.sleep(for: .seconds(60)) } catch { return }
        }
    }

    private func fetch(ip: String) async -> IPReputation? {
        guard let url = URL(string: "https://proxycheck.io/v3/\(ip)") else { return nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        do {
            let (data, response) = try await session.data(from: url)
            guard !Task.isCancelled, let response = response as? HTTPURLResponse else { return nil }
            return IPReputation.parse(data, status: response.statusCode, ip: ip)
        } catch { return nil }
    }
}
