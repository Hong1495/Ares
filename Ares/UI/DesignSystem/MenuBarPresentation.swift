import SwiftUI

/// The menu extra and isolated preview share the exact same presentation.
struct MenuBarPanel: View {
    let country: String?
    let ip: String
    let latency: Int?
    var showsRisk = false
    var risk: Int? = nil
    let download: String
    let upload: String
    let openDashboard: () -> Void
    let openActivity: () -> Void
    let openSettings: () -> Void
    let quit: () -> Void
    var availableVersion: String? = nil
    var openUpdate: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    metric(country.flatMap { $0.isEmpty ? nil : $0.uppercased() } ?? "—", label: "Country")
                        .frame(width: 120, alignment: .leading)
                    metric(ExitIdentity.isAddress(ip) ? ip : "—", label: "Exit IP")
                        .help(ExitIdentity.isAddress(ip) ? ip : "Exit IP unavailable")
                }
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    if showsRisk {
                        metric(risk.map(String.init) ?? "—", label: "IP Risk")
                            .frame(width: 120, alignment: .leading)
                    } else {
                        Color.clear.frame(width: 120, height: 1)
                    }
                    metric(latency.flatMap { $0 > 0 ? String($0) : nil } ?? "—",
                           label: "Latency", unit: "ms", tint: Color.latency(latency))
                }
            }

            Divider().opacity(0.6)

            HStack(alignment: .firstTextBaseline, spacing: 16) {
                speed(download, label: "Download", icon: "arrow.down", tint: .seriesDown)
                    .frame(width: 120, alignment: .leading)
                speed(upload, label: "Upload", icon: "arrow.up", tint: .seriesUp)
            }

            Divider().opacity(0.6)

            if let availableVersion {
                Button(action: openUpdate) {
                    HStack(spacing: 8) {
                        Circle().fill(Color.orange).frame(width: 6, height: 6)
                        Text("Update to \(availableVersion)")
                        Spacer()
                        Image(systemName: "arrow.down.circle")
                    }.font(.system(size: 12, weight: .medium)).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                Button("Open Ares", action: openDashboard)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                action("Activity", icon: "waveform.path", perform: openActivity)
                action("Settings", icon: "gearshape", perform: openSettings)
                action("Quit Ares", icon: "power", perform: quit)
            }.buttonStyle(.plain)
        }
        .padding(16).frame(width: 368)
        .background(DS.canvas).tint(DS.accent)
    }

    private func metric(_ value: String, label: String, unit: String? = nil, tint: Color = .primary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .medium, design: .rounded)).monospacedDigit()
                .foregroundStyle(tint).lineLimit(1).truncationMode(.middle)
            if let unit {
                Text(unit).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).fixedSize()
            }
            Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).fixedSize()
        }.accessibilityElement(children: .ignore)
            .accessibilityLabel("\(label): \(value)\(unit.map { " " + $0 } ?? "")")
    }

    private func speed(_ value: String, label: String, icon: String, tint: Color) -> some View {
        let parts = value.split(separator: " ", maxSplits: 1)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 10, weight: .regular)).foregroundStyle(tint)
                Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            }
            metric(parts.first.map(String.init) ?? "—", label: parts.count > 1 ? String(parts[1]) : "")
        }.accessibilityElement(children: .ignore).accessibilityLabel("\(label): \(value)")
    }

    private func action(_ title: String, icon: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Image(systemName: icon).font(.system(size: 14, weight: .medium))
                .symbolRenderingMode(.monochrome).foregroundStyle(.primary)
                .frame(width: 28, height: 28).contentShape(Rectangle())
        }.help(title).accessibilityLabel(title)
    }
}
