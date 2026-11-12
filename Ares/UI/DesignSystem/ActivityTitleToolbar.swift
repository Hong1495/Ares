import SwiftUI

/// Title/view name stays together; larger values and smaller units share a baseline.
struct ActivityTitleToolbar: ToolbarContent {
    var count: Int
    var topologySummary: String? = nil
    var subtitle: String = "Topology"
    var download: String? = nil
    var upload: String? = nil

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Activity")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }.fixedSize()
                summary
                    .help(download == nil ? "All active connections, grouped by the four topology columns" : "Observed activity traffic since launch or reset; excludes Ares itself. Connections that end between samples may not be captured.")
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.leading, 16)
        }.aresUnframed()
    }

    @ViewBuilder private var summary: some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            if let download, let upload {
                metric("\(count) items")
                metric(download, icon: "arrow.down", tint: .seriesDown)
                metric(upload, icon: "arrow.up", tint: .seriesUp)
            } else {
                let parts = (topologySummary ?? "\(count) processes").components(separatedBy: " · ")
                ForEach(parts.indices, id: \.self) { metric(parts[$0]) }
            }
        }
    }

    private func metric(_ text: String, icon: String? = nil, tint: Color = .secondary) -> some View {
        let parts = text.split(separator: " ", maxSplits: 1)
        return HStack(alignment: .firstTextBaseline, spacing: 4) {
            if let icon {
                Image(systemName: icon).font(.system(size: 10, weight: .medium)).foregroundStyle(tint)
            }
            Text(parts.first.map(String.init) ?? text)
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .monospacedDigit().foregroundStyle(.primary)
            if parts.count > 1 {
                Text(String(parts[1])).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            }
        }.accessibilityElement(children: .ignore)
            .accessibilityLabel(icon == "arrow.down" ? "Download \(text)" : icon == "arrow.up" ? "Upload \(text)" : text)
    }
}
