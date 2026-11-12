import SwiftUI

struct LogsPreview: View {
    let empty: Bool
    @State private var level = "all"
    @State private var search = ""
    @State private var follow = true
    @State private var cleared = false
    @State private var showExport = false
    private var lines: [String] {
        guard !empty && !cleared else { return [] }
        return [
            "18:05:01 [info] Core controller ready",
            "18:05:02 [info] [TCP] api.github.com:443 matched DOMAIN-SUFFIX using Automatic",
            "18:05:03 [debug] DNS cache hit for developer.apple.com",
            "18:05:04 [warning] Health check timed out after 4000 ms",
            "18:05:05 [error] Connection closed by remote peer"
        ].filter { (level == "all" || $0.contains("[\(level)]")) && (search.isEmpty || $0.localizedCaseInsensitiveContains(search)) }
    }
    var body: some View {
        VStack(spacing: 0) {
            LogsTools(level: $level, search: $search, autoScroll: $follow,
                      canClear: !empty && !cleared, canExport: !lines.isEmpty,
                      onClear: { cleared = true }, onExport: { showExport = true })
            Divider()
            LogsSurface(lines: lines, autoScroll: follow, emptyTitle: "No matching logs", emptyDescription: "Change the level or search filter to show logs.")
        }
        .toolbar { CollectionTitleToolbar(title: "Logs", count: lines.count, unit: "Lines") }
        .alert("Preview export", isPresented: $showExport) { Button("Done", role: .cancel) {} }
            message: { Text("\(lines.count) matching lines. Preview does not write files.") }
    }
}
