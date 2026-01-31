import SwiftUI

struct SubscriptionCard: View {
    @EnvironmentObject var profileService: ProfileService

    var body: some View {
        VStack(spacing: 0) {
            // 1. Header Zone
            HStack(spacing: 12) {
                Image(systemName: "creditcard")
                    .font(.system(size: 18, weight: .light))
                    .frame(width: 24, height: 24, alignment: .center)
                    .foregroundStyle(.primary)

                Text("Subscription")
                    .font(.headline.weight(.medium))

                Spacer()

                if let profile = profileService.activeProfile {
                    Text(profile.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(4)
                }

                Button(action: {
                    Task {
                        // Refresh logic if needed, or just reload profiles
                        profileService.loadProfiles()
                        if let id = profileService.activeProfileID {
                            try? await profileService.updateProfile(id: id)
                        }
                    }
                }) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Refresh Subscription")
            }
            .frame(height: 24)
            .padding(16)

            Divider()
                .padding(.horizontal, 16)

            // 2. Content Zone
            if let profile = profileService.activeProfile, let sub = profile.subscriptionInfo {
                VStack(alignment: .leading, spacing: 8) {

                    // Usage Stats
                    HStack {
                        Text("Used")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(formatBytes(sub.upload + sub.download)) / \(formatBytes(sub.total))")
                            .font(.caption)
                            .fontWeight(.medium)
                    }

                    // Progress Bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.gray.opacity(0.15))

                            let fraction = Double(sub.upload + sub.download) / Double(max(sub.total, 1))
                            RoundedRectangle(cornerRadius: 3)
                                .fill(fraction > 0.9 ? Color.red : (fraction > 0.7 ? Color.orange : Color.blue))
                                .frame(width: min(geo.size.width * CGFloat(fraction), geo.size.width))
                        }
                    }
                    .frame(height: 6)

                    // Expiry
                    if let expire = sub.expire {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                            Text("Expires: \(formatDate(expire))")

                            // Days remaining calculation
                            let days = Calendar.current.dateComponents([.day], from: Date(), to: expire).day ?? 0
                            if days < 7 {
                                Text("(\(max(0, days)) days left)")
                                    .foregroundStyle(.red)
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "nosign")
                        .font(.title3)
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text("No Subscription Info")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: 150)
        .cardStyle()
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
