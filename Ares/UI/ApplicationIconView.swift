import SwiftUI

struct ApplicationIconView: View {
    let path: String?

    var body: some View {
        if let path = path, !path.isEmpty {
            Image(nsImage: getAppIcon(from: path))
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "app")
                .foregroundStyle(.secondary)
        }
    }

    private func getAppIcon(from processPath: String) -> NSImage {
        var url = URL(fileURLWithPath: processPath)
        while url.pathExtension != "app" && url.path != "/" {
            url = url.deletingLastPathComponent()
        }
        if url.pathExtension == "app" {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.icon(forFile: processPath)
    }
}
