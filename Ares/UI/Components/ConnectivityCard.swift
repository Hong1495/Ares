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
        .init(id: "google", name: "Google", url: "https://www.google.com", icon: "globe"),
        .init(id: "github", name: "GitHub", url: "https://github.com", icon: "chevron.left.forwardslash.chevron.right"),
        .init(id: "gemini", name: "Gemini", url: "https://gemini.google.com", icon: "sparkles")
    ]

    var body: some View {
        DSCard(padding: 0, spacing: DS.Space.sm) {
            DSCardHeader("Reachability", icon: "antenna.radiowaves.left.and.right", tint: .seriesUp) {
                Button {
                    Task { await testAll() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(DS.Typography.metadata.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .help("Re-test all")
            }

            ForEach(sites) { site in
                row(for: site)
                if site.id != sites.last?.id {
                    Divider().opacity(0.35)
                }
            }
        }
        .task { await testAll() }
    }

    private func row(for site: Site) -> some View {
        HStack(spacing: DS.Space.sm) {
            Image(systemName: site.icon)
                .font(DS.Typography.metadata.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            Text(site.name)
                .font(DS.Typography.secondary.weight(.medium))

            Spacer(minLength: DS.Space.sm)

            if loading.contains(site.id) {
                ProgressView().controlSize(.mini)
            } else if let ms = results[site.id] {
                if ms < 0 {
                    Text("Unreachable")
                        .font(DS.Typography.metadata.weight(.medium))
                        .foregroundStyle(Color.statusBad)
                } else {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.latency(ms))
                            .frame(width: 5, height: 5)
                        Text("\(ms) ms")
                            .font(DS.Typography.metadata.monospaced().weight(.medium))
                            .foregroundStyle(.primary)
                    }
                }
            } else {
                Text("—")
                    .font(DS.Typography.metadata)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture { Task { await test(site) } }
    }

    // MARK: - Probing

    private func testAll() async {
        await withTaskGroup(of: Void.self) { group in
            for site in sites {
                group.addTask { await test(site) }
            }
        }
    }

    @MainActor
    private func test(_ site: Site) async {
        guard !ClashViewModel.shared.isRunning else { return await probe(site) }
        await probe(site)
    }

    @MainActor
    private func probe(_ site: Site) async {
        guard !loading.contains(site.id) else { return }
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

        let start = Date()
        do {
            let (_, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, (200...499).contains(http.statusCode) {
                results[site.id] = Int(Date().timeIntervalSince(start) * 1000)
            } else {
                results[site.id] = -1
            }
        } catch {
            results[site.id] = -1
        }
    }
}
