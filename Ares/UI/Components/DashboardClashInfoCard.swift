import SwiftUI

struct ClashInfoCard: View {
    @State private var memory: Int64 = 0

    var body: some View {
        VStack(spacing: 0) {
            // 1. Header Zone
            HStack(spacing: 12) {
                Image(systemName: "gearshape")
                    .font(.system(size: 18, weight: .light))
                    .frame(width: 24, height: 24, alignment: .center)
                    .foregroundStyle(.primary)

                Text("Clash Core")
                    .font(.headline.weight(.medium))

                Spacer()
            }
            .frame(height: 24)
            .padding(16)

            Divider()
                .padding(.horizontal, 16)

            // 2. Content Zone
            VStack(alignment: .leading, spacing: 4) {
                 HStack {
                    Text("Version")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(clashViewModel.coreVersionInfo.displayVersion)
                        .font(.caption)
                        .fontWeight(.medium)
                        .monospacedDigit()
                }

                HStack {
                    Text("Latest")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(latestVersionText)
                        .font(.caption)
                        .fontWeight(.medium)
                        .monospacedDigit()
                        .foregroundStyle(clashViewModel.isCoreUpdateAvailable ? .orange : .secondary)
                }

                if clashViewModel.isCoreUpdateAvailable {
                    Button {
                        Task { await clashViewModel.installLatestCore() }
                    } label: {
                        Label(clashViewModel.isInstallingCoreUpdate ? "Installing" : "Install Update", systemImage: "arrow.down.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(clashViewModel.isInstallingCoreUpdate || clashViewModel.isRunning)
                }

                if let message = clashViewModel.coreUpdateMessage {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack {
                    Text("Memory")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatMemory(memory))
                        .font(.caption)
                        .fontWeight(.medium)
                        .monospacedDigit()
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 150)
        .cardStyle()
        .task {
            await clashViewModel.refreshCoreVersion()
            await clashViewModel.checkCoreUpdates()

            while !Task.isCancelled {
                _ = await fetchClashInfo()
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }

    private var latestVersionText: String {
        if let latest = clashViewModel.latestCoreRelease {
            return latest.version
        }
        return "Checking..."
    }

    @EnvironmentObject var appState: AppState
    @EnvironmentObject var clashViewModel: ClashViewModel

    @MainActor
    private func fetchClashInfo() async -> Bool {
        if clashViewModel.isToggling { return false }

        let port = appState.tunEnabled ? ClashPorts.apiTun : ClashPorts.apiNormal
        guard let url = URL(string: "http://127.0.0.1:\(port)/version") else { return false }
        // Quick timeout
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2.0
        let session = URLSession(configuration: config)

        do {
            let (data, _) = try await session.data(from: url)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            if json?["version"] as? String != nil {
                self.memory = 10 * 1024 * 1024 // Mock limit
                return true
            }
            return false
        } catch {
            return false
        }
    }

    private func formatMemory(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1024 / 1024
        return String(format: "%.1f MB", mb)
    }
}

/// System Info Card showing system metrics
