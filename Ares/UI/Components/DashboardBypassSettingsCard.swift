import SwiftUI

struct BypassSettingsCard: View {
    @AppStorage("bypassRules") private var bypassRules: String = "localhost, 127.*, 172.16.*, 172.31.*, 192.168.*"

    var ruleArray: [String] {
        bypassRules.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .prefix(3)
            .map { String($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 1. Header Zone
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.turn.up.right.diamond")
                    .font(.system(size: 18, weight: .light))
                    .frame(width: 24, height: 24, alignment: .center)
                    .foregroundStyle(.primary)

                Text("Bypass Rules")
                    .font(.headline.weight(.medium))

                Spacer()
            }
            .frame(height: 24)
            .padding(16)

            Divider()
                .padding(.horizontal, 16)

            // 2. Content Zone
            VStack(alignment: .leading, spacing: 4) {
                ForEach(ruleArray, id: \.self) { rule in
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.green.opacity(0.8))
                        Text(rule)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }

                if ruleArray.count < bypassRules.components(separatedBy: ",").count {
                    Text("+\(bypassRules.components(separatedBy: ",").count - ruleArray.count) more")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(height: 150)
        .cardStyle()
    }
}
