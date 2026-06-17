import SwiftUI

struct MITMConfigCard: View {
    @AppStorage("mitmPorts") private var mitmPorts: String = "80, 443, 8080, 8443, 8888"
    @AppStorage("mitmHosts") private var mitmHosts: String = ""
    @EnvironmentObject var appState: AppState

    var portArray: [String] {
        mitmPorts.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .prefix(3)
            .map { String($0) }
    }

    var hostArray: [String] {
        mitmHosts.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .prefix(2)
            .map { String($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 1. Header Zone
            HStack(spacing: 12) {
                Image(systemName: "eyeglasses")
                    .font(.system(size: 18, weight: .light))
                    .frame(width: 24, height: 24, alignment: .center)
                    .foregroundStyle(.primary)

                Text("MITM Config")
                    .font(.headline.weight(.medium))

                Spacer()
            }
            .frame(height: 24)
            .padding(16)

            Divider()
                .padding(.horizontal, 16)

            // 2. Content Zone
            VStack(alignment: .leading, spacing: 6) {
                // Ports
                HStack {
                    Text("Ports")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(portArray.joined(separator: ", "))
                        .font(.caption)
                        .fontWeight(.medium)
                        .monospacedDigit()
                        .lineLimit(1)
                }

                // Whitelist
                if !hostArray.isEmpty {
                    HStack {
                        Text("Whitelist")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(hostArray.count) host(s)")
                            .font(.caption)
                            .fontWeight(.medium)
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

/// Bypass Settings Card - Shows bypass rules
