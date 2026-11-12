import SwiftUI

/// Reachability probes. Each row is a real HEAD request through whatever
/// routing is currently active, so it reflects the user's actual path.
struct ConnectivityCard: View {
    @State private var results: [String: Int] = [:]
    @State private var loading: Set<String> = []

    private struct Site: Identifiable {
        let id: String
        let name: String
        let url: String
        let icon: String
    }

    private let sites: [Site] = [
        .init(id: "google", name: "Google", url: "https://www.google.com", icon: "magnifyingglass"),
        .init(id: "github", name: "GitHub", url: "https://github.com", icon: "chevron.left.forwardslash.chevron.right"),
        .init(id: "gemini", name: "Gemini", url: "https://gemini.google.com", icon: "sparkles")
    ]

    var body: some View {
        OverviewReachability(
            items: sites.map { .init(id: $0.id, name: $0.name, icon: $0.icon,
                                    latency: results[$0.id], loading: loading.contains($0.id)) }
        )
        .task { await monitor() }
    }

    // MARK: - Probing

    private func monitor() async {
        let clock = ContinuousClock()
        while !Task.isCancelled {
            let nextCheck = clock.now.advanced(by: .seconds(30))
            await testAll()
            do {
                try await clock.sleep(until: nextCheck)
            } catch {
                return
            }
        }
    }

    private func testAll() async {
        await withTaskGroup(of: Void.self) { group in
            for site in sites {
                group.addTask { await probe(site) }
            }
        }
    }

    @MainActor
    private func probe(_ site: Site) async {
        guard !Task.isCancelled, !loading.contains(site.id) else { return }
        loading.insert(site.id)
        defer { loading.remove(site.id) }

        guard let url = URL(string: site.url) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 4
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 4
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        let clock = ContinuousClock()
        let start = clock.now
        do {
            let (_, response) = try await session.data(for: request)
            guard !Task.isCancelled else { return }
            if let http = response as? HTTPURLResponse, (200...499).contains(http.statusCode) {
                let elapsed = start.duration(to: clock.now).components
                results[site.id] = Int(elapsed.seconds * 1000 + elapsed.attoseconds / 1_000_000_000_000_000)
            } else {
                results[site.id] = -1
            }
        } catch {
            guard !Task.isCancelled else { return }
            results[site.id] = -1
        }
    }
}
