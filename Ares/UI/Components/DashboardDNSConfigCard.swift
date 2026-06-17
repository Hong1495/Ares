import SwiftUI

struct DNSConfigCard: View {
    @AppStorage("dnsServers") private var dnsServers: String = "223.5.5.5, 8.8.8.8"

    var dnsArray: [String] {
        dnsServers.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .prefix(2)
            .map { String($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 1. Header Zone
            HStack(spacing: 12) {
                Image(systemName: "network.badge.shield.half.filled")
                    .font(.system(size: 18, weight: .light))
                    .frame(width: 24, height: 24, alignment: .center)
                    .foregroundStyle(.primary)

                Text("DNS")
                    .font(.headline.weight(.medium))

                Spacer()
            }
            .frame(height: 24)
            .padding(16)

            Divider()
                .padding(.horizontal, 16)

            // 2. Content Zone
            VStack(alignment: .leading, spacing: 4) {
                ForEach(dnsArray, id: \.self) { dns in
                    HStack(spacing: 6) {
                        Image(systemName: "server.rack")
                            .font(.caption)
                            .foregroundStyle(.blue.opacity(0.8))
                        Text(dns)
                            .font(.caption)
                            .fontWeight(.medium)
                            .monospacedDigit()
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(height: 150)
        .cardStyle()
    }
}

/// MITM Config Card - Shows MITM ports and whitelist
