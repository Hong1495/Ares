import SwiftUI

struct DNSConfigCard: View {
    @AppStorage(DefaultsKeys.dnsServers) private var dnsServers: String = "223.5.5.5, 119.29.29.29"

    private var servers: [String] {
        dnsServers
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        DSCard(padding: 0, spacing: DS.Space.sm) {
            DSCardHeader("DNS", icon: "network.badge.shield.half.filled", tint: .seriesDown)

            if servers.isEmpty {
                Text("No resolvers configured")
                    .font(DS.Typography.secondary)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(servers.enumerated()), id: \.offset) { _, server in
                    Text(server)
                        .font(DS.Typography.secondary.monospaced().weight(.medium))
                        .textSelection(.enabled)
                }
            }
        }
    }
}

struct BypassSettingsCard: View {
    @AppStorage(DefaultsKeys.bypassRules)
    private var bypassRules: String = "localhost, 127.*, 10.*, 172.16.*, 172.31.*, 192.168.*"

    private var rules: [String] {
        bypassRules
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        DSCard(padding: 0, spacing: DS.Space.sm) {
            DSCardHeader(
                "Bypass",
                icon: "arrow.triangle.turn.up.right.diamond",
                tint: .seriesDown
            )

            if rules.isEmpty {
                Text("No bypass rules")
                    .font(DS.Typography.secondary)
                    .foregroundStyle(.secondary)
            } else {
                Text(rules.joined(separator: " · "))
                    .font(DS.Typography.metadata.monospaced())
                    .foregroundStyle(.secondary)
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }
}
