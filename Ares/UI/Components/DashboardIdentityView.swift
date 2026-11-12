import SwiftUI

/// Owns the existing exit-identity refresh lifecycle at the dashboard title.
struct DashboardIdentityView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var clashViewModel: ClashViewModel
    @EnvironmentObject var clashController: ClashController

    var body: some View {
        DashboardTitleSummary(country: appState.countryCode, ip: appState.publicIP,
            latency: clashViewModel.isRunning && appState.currentMode != .direct ? clashController.primaryLatency : nil)
            .task { await monitor() }
    }

    // MARK: - Work

    private func monitor() async {
        await refresh()

        var lastMode = appState.currentMode
        var lastNode = activeNodeName()

        while !Task.isCancelled {
            do { try await Task.sleep(for: .seconds(10)) } catch { return }
            if clashViewModel.isRunning && !clashViewModel.isToggling && appState.currentMode != .direct,
               let node = clashController.primaryNodeName {
                _ = try? await clashController.testProxyDelay(name: node, timeout: 2000)
            }
            guard !Task.isCancelled else { return }
            let mode = appState.currentMode
            let node = activeNodeName()
            if mode != lastMode || node != lastNode {
                lastMode = mode
                lastNode = node
                do { try await Task.sleep(for: .milliseconds(800)) } catch { return }
                await refresh()
            }
        }
    }

    private func activeNodeName() -> String? {
        if appState.currentMode == .global {
            return clashController.proxyGroups.first { $0.name == "GLOBAL" }?.now
        }
        let groups = clashController.proxyGroups
        if let g = groups.first(where: { $0.name == "🚀 节点选择" }) { return g.now }
        if let g = groups.first(where: { $0.name == "Proxy" }) { return g.now }
        return groups.first { $0.type == "Selector" && $0.name != "GLOBAL" }?.now
    }

    private func refresh() async {
        await fetchPublicIP()
    }

    private func fetchPublicIP() async {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8

        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let endpoints = [
            "https://api.ipify.org?format=json",
            "https://ifconfig.co/json",
            "https://api.ip.sb/geoip",
            "https://ipapi.co/json/"
        ]

        var hasIP = false
        var hasGeo = false

        await withTaskGroup(of: (String, String?)?.self) { group in
            for endpoint in endpoints {
                group.addTask {
                    guard let url = URL(string: endpoint) else { return nil }
                    do {
                        let (data, _) = try await session.data(from: url)
                        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            let ip = json["ip"] as? String ?? json["address"] as? String
                            let country = json["country_code"] as? String ?? json["country"] as? String
                            if let ip { return (ip, country) }
                        }
                    } catch {}
                    return nil
                }
            }

            for await result in group {
                guard let (ip, country) = result else { continue }
                guard !Task.isCancelled else { group.cancelAll(); return }
                await MainActor.run { appState.updateIPInfo(ip: ip, country: country) }
                hasIP = true
                if country != nil { hasGeo = true }
                if hasIP && hasGeo {
                    group.cancelAll()
                    return
                }
            }
        }

        if !hasIP && !Task.isCancelled {
            await MainActor.run { appState.updateIPInfo(ip: "Offline", country: nil) }
        }
    }
}
