import SwiftUI

struct MITMConfigCard: View {
    @AppStorage(DefaultsKeys.mitmPorts) private var mitmPorts: String = "80, 443, 8080, 8443"
    @AppStorage(DefaultsKeys.mitmHosts) private var mitmHosts: String = ""
    @EnvironmentObject var appState: AppState
    @ObservedObject private var certManager = CertificateManager.shared

    private var ports: [String] {
        mitmPorts
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var hosts: [String] {
        mitmHosts
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        DSCard(padding: 0, spacing: DS.Space.sm) {
            DSCardHeader("MITM", icon: "eye", tint: .seriesUp)

            DSKeyValueRow(
                label: "Certificate",
                value: certManager.isRootCAInstalled ? "Installed" : "Not installed",
                valueTint: certManager.isRootCAInstalled ? Color.statusGood : Color.statusBad,
                monospaced: false
            )

            DSKeyValueRow(
                label: "Ports",
                value: ports.isEmpty ? "—" : ports.joined(separator: ", ")
            )

            DSKeyValueRow(
                label: "Scope",
                value: hosts.isEmpty ? "All hosts" : "\(hosts.count) host(s)",
                monospaced: false
            )
        }
    }
}

struct ClashInfoCard: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var clashViewModel: ClashViewModel
    @State private var apiReachable: Bool?

    var body: some View {
        DSCard(padding: 0, spacing: DS.Space.sm) {
            DSCardHeader("Core", icon: "cpu", tint: .seriesDown)

            DSKeyValueRow(
                label: "Latest release",
                value: clashViewModel.latestCoreRelease?.version ?? "Checking…",
                valueTint: clashViewModel.isCoreUpdateAvailable ? Color.statusWarn : Color.secondary
            )

            DSKeyValueRow(
                label: "API",
                value: apiReachable == nil ? "Checking…" : (apiReachable! ? "Reachable" : "Unreachable"),
                valueTint: apiReachable == true ? Color.statusGood : (apiReachable == false ? Color.statusBad : Color.secondary),
                monospaced: false
            )

            if clashViewModel.isCoreUpdateAvailable {
                Button {
                    Task { await clashViewModel.installLatestCore() }
                } label: {
                    Label(
                        clashViewModel.isInstallingCoreUpdate ? "Installing…" : "Install update",
                        systemImage: "arrow.down.circle"
                    )
                    .font(DS.Typography.metadata.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(clashViewModel.isInstallingCoreUpdate || clashViewModel.isRunning)
                .padding(.top, DS.Space.xxs)
            }

            if let message = clashViewModel.coreUpdateMessage {
                Text(message)
                    .font(DS.Typography.metadata)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .task {
            await clashViewModel.refreshCoreVersion()
            while !Task.isCancelled {
                await checkAPI()
                try? await Task.sleep(nanoseconds: 15_000_000_000)
            }
        }
    }

    private func checkAPI() async {
        let port = appState.tunEnabled ? ClashPorts.apiTun : ClashPorts.apiNormal
        guard let url = URL(string: "http://127.0.0.1:\(port)/version") else { return }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2
        let session = URLSession(configuration: config)
        do {
            let (_, response) = try await session.data(from: url)
            apiReachable = (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            apiReachable = false
        }
    }
}

struct SystemInfoCard: View {
    @State private var architecture = "—"
    @State private var osVersion = "—"
    @State private var memory = "—"

    var body: some View {
        DSCard(padding: 0, spacing: DS.Space.sm) {
            DSCardHeader("System", icon: "desktopcomputer", tint: .seriesDown)

            Text("macOS \(osVersion) · \(architecture)")
                .font(DS.Typography.secondary)
            Text("\(memory) memory")
                .font(DS.Typography.metadata).foregroundStyle(.secondary)
                .help("Physical memory")
        }
        .task {
            await Task.yield()
            fetchSystemInfo()
        }
    }

    private func fetchSystemInfo() {
        var sysinfo = utsname()
        uname(&sysinfo)
        let machine = withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        let version = ProcessInfo.processInfo.operatingSystemVersion
        architecture = machine
        osVersion = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        memory = String(format: "%.0f GB", Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824)
    }
}
