import SwiftUI

struct DashboardTitleSummary: View {
    let country: String?
    let ip: String
    let latency: Int?

    private var countryName: String {
        guard let country, !country.isEmpty else { return "—" }
        return country.uppercased()
    }

    var body: some View {
        HStack(spacing: 24) {
            Text("Dashboard").font(.system(size: 13, weight: .semibold))
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                item(countryName, label: "Country")
                item(ExitIdentity.isAddress(ip) ? ip : "—", label: "Exit IP")
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(latency.flatMap { $0 > 0 ? String($0) : nil } ?? "—")
                        .font(.system(size: 18, weight: .medium, design: .rounded)).monospacedDigit()
                        .foregroundStyle(Color.latency(latency))
                    Text("ms").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    Text("Latency").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                }.help("Selected proxy latency")
            }
        }.foregroundStyle(.primary).lineLimit(1).fixedSize(horizontal: true, vertical: false)
    }
    private func item(_ value: String, label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value).font(.system(size: 18, weight: .medium, design: .rounded)).monospacedDigit()
            Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
        }.accessibilityElement(children: .ignore).accessibilityLabel("\(label): \(value)")
    }
}
