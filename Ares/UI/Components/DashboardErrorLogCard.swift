import SwiftUI

struct ErrorLogCard: View {
    @EnvironmentObject var clashViewModel: ClashViewModel

    // Filtered logs
    var errorLogs: [String] {
        clashViewModel.logs.filter { $0.contains("⚠️") || $0.contains("❌") || $0.lowercased().contains("error") || $0.lowercased().contains("fail") }
            .suffix(2) // Last 2 only
            .reversed() // Newest first
    }

    var body: some View {
        VStack(spacing: 0) {
            // 1. Header Zone
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 18, weight: .light))
                    .frame(width: 24, height: 24, alignment: .center)

                Text("Error Logs")
                    .font(.headline.weight(.medium))

                Spacer()
            }
            .frame(height: 24)
            .foregroundStyle(errorLogs.isEmpty ? Color.primary : Color.orange)
            .padding(16)

            Divider()
                .padding(.horizontal, 16)

            // 2. Content Zone
            VStack(alignment: .leading, spacing: 4) {
                 if errorLogs.isEmpty {
                    HStack {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(.green)
                        Text("No active errors")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(errorLogs, id: \.self) { log in
                            Text(cleanLog(log))
                                .font(.caption2) // Tiny text for logs
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(height: 150)
        .cardStyle()
    }

    func cleanLog(_ log: String) -> String {
        return log
    }
}

/// DNS Config Card - Shows DNS settings
