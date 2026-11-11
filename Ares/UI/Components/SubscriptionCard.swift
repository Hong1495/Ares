import SwiftUI

struct SubscriptionCard: View {
    @EnvironmentObject var profileService: ProfileService

    var body: some View {
        DSCard(padding: 0, spacing: DS.Space.sm) {
            DSCardHeader(
                profileService.activeProfile?.name ?? "Subscription",
                icon: "creditcard",
                tint: .seriesDown
            ) {
                Button {
                    Task { await refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(DS.Typography.metadata.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .help("Refresh subscription")
            }

            if let sub = profileService.activeProfile?.subscriptionInfo {
                usage(sub)
            } else {
                Text("No subscription")
                    .font(DS.Typography.secondary)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, DS.Space.xs)
            }
        }
    }

    @ViewBuilder
    private func usage(_ sub: SubscriptionInfo) -> some View {
        let fraction = sub.total > 0
            ? min(Double(sub.used) / Double(sub.total), 1)
            : 0

        VStack(alignment: .leading, spacing: DS.Space.sm) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.xs) {
                Text(Self.formatBytes(sub.used))
                    .font(DS.Typography.title.weight(.semibold))
                    .monospacedDigit()
                Text("of \(Self.formatBytes(sub.total))")
                    .font(DS.Typography.metadata)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("\(Int(fraction * 100))%")
                    .font(DS.Typography.metadata.monospaced().weight(.medium))
                    .foregroundStyle(fraction > 0.9 ? Color.statusBad : Color.secondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(fraction > 0.9 ? Color.statusBad : Color.seriesDown)
                        .frame(width: max(geo.size.width * fraction, fraction > 0 ? 4 : 0))
                }
            }
            .frame(height: 5)

            if let expire = sub.expire {
                let days = Calendar.current.dateComponents([.day], from: Date(), to: expire).day ?? 0
                HStack(spacing: DS.Space.xs) {
                    Text("Expires \(expire.formatted(date: .abbreviated, time: .omitted))")
                        .foregroundStyle(.secondary)
                    if days <= 7 {
                        DSTag(text: days <= 0 ? "Expired" : "\(days) days left", tint: .statusBad)
                    }
                }
                .font(DS.Typography.metadata)
            }
        }
    }

    private func refresh() async {
        if let id = profileService.activeProfileID {
            do { try await profileService.updateProfile(id: id) }
            catch is CancellationError { }
            catch { AppState.shared.reportError(error.localizedDescription) }
        }
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
