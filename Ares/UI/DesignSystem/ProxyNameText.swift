import AppKit
import SwiftUI

@MainActor enum ProxyNameText {
    private static let flagSize = NSSize(width: 16, height: 12)

    private static let flags: [String: NSImage] = {
        guard let folder = Bundle.main.resourceURL?.appendingPathComponent("ProxyFlags", isDirectory: true),
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return [:] }
        return Dictionary(uniqueKeysWithValues: files.compactMap { file in
            guard file.pathExtension == "png", let image = NSImage(contentsOf: file) else { return nil }
            let flag = NSImage(size: flagSize, flipped: false) { rect in
                image.draw(in: rect)
                NSColor(white: 0.5, alpha: 0.65).setStroke()
                let border = NSBezierPath(rect: rect.insetBy(dx: 0.25, dy: 0.25))
                border.lineWidth = 0.5
                border.stroke()
                return true
            }
            let code = file.deletingPathExtension().lastPathComponent.uppercased()
            return (code, flag)
        })
    }()

    static func label(_ name: String) -> Text {
        let segments = ProxyFlag.segments(in: name)
        guard !segments.isEmpty, segments != [.text(name)] else { return Text(verbatim: name) }
        return segments.reduce(Text(verbatim: "")) { label, segment in
            let part: Text
            switch segment {
            case .text(let text): part = Text(verbatim: text)
            case .flag(let code):
                if let flag = flags[code] {
                    part = Text(Image(nsImage: flag).renderingMode(.original))
                } else {
                    part = Text(verbatim: "[\(code)]")
                }
            }
            return Text("\(label)\(part)")
        }.accessibilityLabel(Text(verbatim: ProxyFlag.plainName(name)))
    }
}
