import SwiftUI

struct IpAddressCard: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var clashViewModel: ClashViewModel
    @EnvironmentObject var clashController: ClashController

    @State private var localIP: String = "..."
    @State private var networkType: String = "..."

    // Track current node/mode to detect changes
    @State private var lastNode: String? = nil
    @State private var lastMode: ClashConfig.Mode? = nil

    var body: some View {
        VStack(spacing: 0) {
            // 1. Header Zone
            HStack(spacing: 12) {
                Image(systemName: "globe.americas")
                    .font(.system(size: 18, weight: .light))
                    .frame(width: 24, height: 24, alignment: .center)
                    .foregroundStyle(.primary)

                Text("IP Address")
                    .font(.headline.weight(.medium))

                Spacer()

                // Refresh Button
                Button(action: {
                    Task { await refreshAll() }
                }) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
            .frame(height: 24)
            .padding(16)

            Divider()
                .padding(.horizontal, 16)

            // 2. Content Zone
            VStack(alignment: .leading, spacing: 8) {
                // Public IP
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Public / Exit")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        if isProxyActive {
                            Text("PROXY")
                                .font(.system(size: 8, weight: .bold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.blue.opacity(0.1))
                                .foregroundStyle(.blue)
                                    .cornerRadius(3)
                        }
                    }

                    HStack(spacing: 6) {
                        Text(appState.publicIP)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .monospacedDigit()

                        if let country = appState.countryCode {
                            Text(country)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }
                }

                // Local IP
                VStack(alignment: .leading, spacing: 2) {
                    Text("Local (\(networkType))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(localIP)
                        .font(.subheadline)
                        .monospacedDigit()
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(height: 150)
        .cardStyle()
        .task {
            await refreshAll()

            // Watch for changes
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)

                let currentMode = appState.currentMode
                let nodeSelection = getActiveNodeName()

                if currentMode != lastMode || nodeSelection != lastNode {
                    // Optimized stabilization delay: 0.8s
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    await refreshAll()
                }
            }
        }
    }

    private var isProxyActive: Bool {
        clashViewModel.isRunning && appState.currentMode != .direct
    }

    private func getActiveNodeName() -> String? {
        if appState.currentMode == .global {
            return clashController.proxyGroups.first(where: { $0.name == "GLOBAL" })?.now
        }
        let allGroups = clashController.proxyGroups
        if let exact = allGroups.first(where: { $0.name == "🚀 节点选择" }) { return exact.now }
        if let exact = allGroups.first(where: { $0.name == "Proxy" }) { return exact.now }
        if let fallback = allGroups.first(where: { $0.type == "Selector" && $0.name != "GLOBAL" }) { return fallback.now }
        return nil
    }

    private func refreshAll() async {
        await MainActor.run {
            appState.publicIP = "Fetching..."
        }
        updateLocalIP()
        self.lastMode = appState.currentMode
        self.lastNode = getActiveNodeName()
        await fetchPublicIP()
    }

    private func updateLocalIP() {
        let (ip, type) = fetchLocalIP()
        self.localIP = ip
        self.networkType = type
    }

    private func fetchLocalIP() -> (String, String) {
        var address: String = "127.0.0.1"
        var type: String = "Unknown"
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&ifaddr) == 0 {
            var ptr = ifaddr
            while ptr != nil {
                defer { ptr = ptr?.pointee.ifa_next }
                guard let interface = ptr?.pointee else { continue }
                let name = String(cString: interface.ifa_name)
                let addrFamily = interface.ifa_addr.pointee.sa_family
                if addrFamily == UInt8(AF_INET) {
                    if name == "en0" || name == "en1" {
                        type = "WiFi/Ethernet"
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                    &hostname, socklen_t(hostname.count),
                                    nil, socklen_t(0), NI_NUMERICHOST)
                        address = String(cString: hostname)
                    }
                }
            }
            freeifaddrs(ifaddr)
        }
        return (address, type)
    }

    private func fetchPublicIP() async {
        // TUN routes traffic globally, system proxy is picked up by .default config automatically.
        // No manual connectionProxyDictionary needed — it causes routing conflicts.
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8.0

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
                            if let ip = ip { return (ip, country) }
                        }
                    } catch {}
                    return nil
                }
            }

            for await result in group {
                if let (ip, country) = result {
                    await MainActor.run {
                        appState.updateIPInfo(ip: ip, country: country)
                    }

                    if !hasIP { hasIP = true }
                    if country != nil { hasGeo = true }

                    if hasIP && hasGeo {
                        group.cancelAll()
                        return
                    }
                }
            }
        }

        if !hasIP {
            await MainActor.run {
                appState.updateIPInfo(ip: "Offline", country: nil)
            }
        }
    }
}

/// Clash Info Card showing core information
