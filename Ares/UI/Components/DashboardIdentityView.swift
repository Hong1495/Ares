import SwiftUI

struct DashboardIdentityView: View {
    @AppStorage(DefaultsKeys.ipReputationEnabled) private var reputationEnabled = false
    @ObservedObject private var reputation = IPReputationService.shared
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var clashViewModel: ClashViewModel
    @EnvironmentObject var clashController: ClashController

    // Cancel an in-flight query when its route changes, including core startup.
    private var routeKey: String {
        "\(clashController.runtimeGeneration)|\(clashViewModel.runtimeState.isAPIReady)|\(clashViewModel.isToggling)|\(appState.systemProxyEnabled)|\(appState.tunEnabled)|\(appState.currentMode)|\(clashController.primaryNodeName ?? "")"
    }

    var body: some View {
        DashboardTitleSummary(country: appState.countryCode, ip: appState.publicIP,
            latency: clashViewModel.isRunning && appState.currentMode != .direct ? clashController.primaryLatency : nil,
            showsRisk: reputationEnabled,
            risk: reputation.result?.ip == appState.publicIP ? reputation.result?.risk : nil,
            riskHelp: reputationHelp)
            .task(id: routeKey) { await monitor() }
            .task(id: "\(reputationEnabled)|\(appState.publicIP)|\(routeKey)") {
                await reputation.monitor(ip: appState.publicIP, enabled: reputationEnabled && !clashViewModel.isToggling)
            }
    }

    private var reputationHelp: String {
        guard let result = reputation.result, result.ip == appState.publicIP else {
            return reputation.checking ? "Checking IP risk…" : "IP risk unavailable · proxycheck.io"
        }
        let types = result.types.isEmpty ? "No type flags" : result.types.joined(separator: ", ")
        return "proxycheck.io · \(result.risk)/100 risk (lower is better) · \(types) · Checked \(result.checkedAt.formatted()) · VPN and hosting classification can increase this score; it is not a purity percentage."

    }

    private func monitor() async {
        let key = routeKey
        appState.updateIPInfo(ip: "—", country: nil)
        guard !clashViewModel.isToggling else { return }
        var nextRefresh = Date.distantPast
        while !Task.isCancelled {
            if appState.isForeground {
                if Date() >= nextRefresh {
                    let result = await fetchIdentity()
                    guard !Task.isCancelled, key == routeKey else { return }
                    appState.updateIPInfo(ip: result?.ip ?? "—", country: result?.country)
                    // Retry missing data; never stay stuck after a startup failure.
                    nextRefresh = Date().addingTimeInterval(result?.country == nil ? 30 : 120)
                }
                if clashViewModel.isRunning && !clashViewModel.isToggling && appState.currentMode != .direct,
                   let node = clashController.primaryNodeName {
                    _ = try? await clashController.testProxyDelay(name: node, timeout: 2000)
                }
            }
            do { try await Task.sleep(for: .seconds(10)) } catch { return }
        }
    }

    private func fetchIdentity() async -> ExitIdentity? {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 10
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let endpoints = [
            "https://ifconfig.co/json",
            "https://api.ip.sb/geoip",
            "https://www.cloudflare.com/cdn-cgi/trace",
            "https://api.ipify.org?format=json"
        ]
        return await withTaskGroup(of: ExitIdentity?.self) { group in
            for endpoint in endpoints {
                group.addTask {
                    guard let url = URL(string: endpoint) else { return nil }
                    do {
                        let (data, response) = try await session.data(from: url)
                        guard !Task.isCancelled, let response = response as? HTTPURLResponse else { return nil }
                        return ExitIdentity.parse(data, status: response.statusCode)
                    } catch { return nil }
                }
            }
            var fallback: ExitIdentity?
            for await result in group {
                guard !Task.isCancelled else { group.cancelAll(); return nil }
                guard let result else { continue }
                if result.country != nil { group.cancelAll(); return result }
                if fallback == nil { fallback = result }
            }
            return fallback
        }
    }
}
