import SwiftUI

/// Primary proxy group. Reads the adaptive group so it works
/// across subscription naming conventions.
struct CurrentProxyCard: View {
    @EnvironmentObject var clashController: ClashController
    @EnvironmentObject var clashViewModel: ClashViewModel
    @EnvironmentObject var appState: AppState


    var body: some View {
        DSCard(padding: 0, spacing: DS.Space.md) {
            DSCardHeader(
                "Proxy",
                icon: "server.rack",
                tint: .seriesDown
            )

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

}
