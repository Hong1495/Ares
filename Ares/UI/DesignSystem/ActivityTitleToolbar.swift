import SwiftUI

/// The title and view name form one block; statistics align to its vertical center.
struct ActivityTitleToolbar: ToolbarContent {
    var count: Int
    var topologySummary: String? = nil
    var topologySubtitle: String = "Topology"
    var download: String? = nil
    var upload: String? = nil

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            HStack(alignment: .center, spacing: 20) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Activity")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(download == nil ? topologySubtitle : "Connections")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .fixedSize()
                summary
                    .font(.system(size: 12, weight: .regular))
                    .help(download == nil ? "All active connections, grouped by the four topology columns" : "Observed activity traffic since launch or reset; excludes Ares itself. Connections that end between samples may not be captured.")
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            // Keep enough intrinsic width when switching from process count to traffic.
            .frame(width: topologySummary == nil ? 350 : 470, alignment: .leading)
            .padding(.leading, 16)
        }.aresUnframed()
    }

    private var summary: Text {
        if let download, let upload {
            return Text("\(count) items   ")
                + Text(Image(systemName: "arrow.down")).foregroundColor(.seriesDown)
                + Text(" \(download)   ")
                + Text(Image(systemName: "arrow.up")).foregroundColor(.seriesUp)
                + Text(" \(upload)")
        }
        return Text(topologySummary ?? "\(count) processes")
    }
}
