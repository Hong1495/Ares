import SwiftUI

/// Public egress + local interface identity.
struct ExitIdentityCard: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var clashViewModel: ClashViewModel
    @EnvironmentObject var clashController: ClashController

    @State private var localIP = "—"
    @State private var networkType = "Unknown"
    @State private var isRefreshing = false

    var body: some View {
        DSCard(padding: 0, spacing: DS.Space.md) {
            DSCardHeader("IP address", icon: "globe.americas", tint: .seriesDown) {
                Button {
                    Task { await refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(DS.Typography.metadata.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .disabled(isRefreshing)
                .help("Refresh public IP")
            }

            VStack(alignment: .leading, spacing: DS.Space.sm) {
                HStack(spacing: DS.Space.sm) {
                    Text(appState.publicIP)
                        .font(DS.Typography.title.monospaced().weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if let country = appState.countryCode, !country.isEmpty {
                        DSTag(text: country, tint: .secondary)
                    }

                    Spacer(minLength: 0)

                }

                DSKeyValueRow(label: "Local", value: "\(localIP) · \(networkType)")
            }


        }
        .task { await monitor() }
    }

    // MARK: - Work

    private func monitor() async {
        updateLocalIP()
        await refresh()

        var lastMode = appState.currentMode
        var lastNode = activeNodeName()

        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            let mode = appState.currentMode
            let node = activeNodeName()
            if mode != lastMode || node != lastNode {
                lastMode = mode
                lastNode = node
                try? await Task.sleep(nanoseconds: 800_000_000)
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
        await MainActor.run { isRefreshing = true }
        updateLocalIP()
        await fetchPublicIP()
        await MainActor.run { isRefreshing = false }
    }

    private func updateLocalIP() {
        var address = "—"
        var type = "Unknown"
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&ifaddr) == 0 {
            var ptr = ifaddr
            while ptr != nil {
                defer { ptr = ptr?.pointee.ifa_next }
                guard let interface = ptr?.pointee else { continue }
                let name = String(cString: interface.ifa_name)
                if interface.ifa_addr.pointee.sa_family == UInt8(AF_INET),
                   name == "en0" || name == "en1" {
                    type = name == "en0" ? "Wi-Fi" : "Ethernet"
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(
                        interface.ifa_addr,
                        socklen_t(interface.ifa_addr.pointee.sa_len),
                        &hostname, socklen_t(hostname.count),
                        nil, socklen_t(0), NI_NUMERICHOST
                    )
                    address = String(cString: hostname)
                }
            }
            freeifaddrs(ifaddr)
        }
        localIP = address
        networkType = type
    }

    private func fetchPublicIP() async {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8

        let session = URLSession(configuration: config)
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
                await MainActor.run { appState.updateIPInfo(ip: ip, country: country) }
                hasIP = true
                if country != nil { hasGeo = true }
                if hasIP && hasGeo {
                    group.cancelAll()
                    return
                }
            }
        }

        if !hasIP {
            await MainActor.run { appState.updateIPInfo(ip: "Offline", country: nil) }
        }
    }
}
