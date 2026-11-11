import SwiftUI

/// Primary proxy group with live latency. Reads the adaptive group so it works
/// across subscription naming conventions.
struct CurrentProxyCard: View {
    @EnvironmentObject var clashController: ClashController
    @EnvironmentObject var clashViewModel: ClashViewModel
    @EnvironmentObject var appState: AppState

    @State private var latency: Int?
    @State private var isTesting = false

    var body: some View {
        DSCard(padding: 0, spacing: DS.Space.md) {
            DSCardHeader(
                "Proxy",
                icon: "server.rack",
                tint: .seriesDown
            ) {
                Button {
                    Task { await testNow() }
                } label: {
                    Image(systemName: "bolt.horizontal")
                        .font(DS.Typography.metadata.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .disabled(isTesting || !clashViewModel.isRunning)
                .help("Measure latency")
            }

            if appState.currentMode == .direct {
                HStack(spacing: DS.Space.sm) {
                    Image(systemName: "arrow.turn.up.right")
                        .foregroundStyle(.secondary)
                    Text("Direct connection")
                        .font(DS.Typography.secondary)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, DS.Space.sm)
            } else if let group, let now = group.now {
                HStack(alignment: .center, spacing: DS.Space.md) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(now)
                            .font(DS.Typography.body.weight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(group.name)
                            .font(DS.Typography.metadata)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: DS.Space.sm)

                    if isTesting {
                        ProgressView().controlSize(.mini)
                    } else {
                        HStack(alignment: .lastTextBaseline, spacing: 2) {
                            Text(latency.map(String.init) ?? "--")
                                .font(DS.Typography.metric)
                                .monospacedDigit()
                                .foregroundStyle(Color.latency(latency))
                            Text("ms")
                                .font(DS.Typography.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                HStack(spacing: DS.Space.sm) {
                    Image(systemName: "questionmark.circle")
                        .foregroundStyle(.secondary)
                    Text(clashViewModel.isRunning ? "No proxy group available" : "Core stopped")
                        .font(DS.Typography.secondary)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, DS.Space.sm)
            }


        }
        .task { await pollLatency() }
    }

    // MARK: - Data

    private var group: ProxyGroup? {
        if appState.currentMode == .global {
            return clashController.proxyGroups.first { $0.name == "GLOBAL" }
        }
        let groups = clashController.proxyGroups.filter { $0.name != "GLOBAL" }
        if let exact = groups.first(where: { $0.name == "🚀 节点选择" }) { return exact }
        if let exact = groups.first(where: { $0.name == "Proxy" }) { return exact }
        if let exact = groups.first(where: { $0.name == "PROXY" }) { return exact }
        if let partial = groups.first(where: { $0.name.contains("节点") && $0.type == "Selector" }) { return partial }
        return groups.first { $0.type == "Selector" }
    }

    private func pollLatency() async {
        while !Task.isCancelled {
            await testNow()
            try? await Task.sleep(nanoseconds: 10_000_000_000)
        }
    }

    private func testNow() async {
        guard clashViewModel.isRunning, !clashViewModel.isToggling else { return }
        guard let node = group?.now else { return }
        await MainActor.run { isTesting = true }
        let result = try? await clashController.testProxyDelay(name: node, timeout: 2000)
        await MainActor.run {
            withAnimation(.easeOut(duration: 0.2)) { latency = result }
            isTesting = false
        }
    }
}
