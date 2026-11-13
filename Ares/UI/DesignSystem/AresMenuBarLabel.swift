import SwiftUI
import AppKit

/// Template artwork lets macOS choose its menu-bar tint independently of the
/// app's theme, including wallpaper-driven appearance and selection highlighting.
struct AresMenuBarLabel: View {
    var showsLatency: Bool
    var latency: Int?

    var body: some View {
        // MenuBarExtra can discard nested text/layout when bridging to NSStatusItem.
        // One template image preserves the unit and spacing with native adaptive tint.
        Image(nsImage: Self.statusImage(showsLatency: showsLatency, latency: latency))
        .renderingMode(.template)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ares")
        .accessibilityValue(showsLatency ? latencyDescription : "")
    }

    private var latencyDescription: String {
        guard let latency else { return "Latency not measured" }
        return latency > 0 ? "\(latency) milliseconds" : "Node unavailable"
    }

    static func statusImage(showsLatency: Bool, latency: Int?) -> NSImage {
        guard showsLatency else { return boarImage }
        let number = NSAttributedString(
            string: latency.map { $0 > 0 ? "\($0)" : "--" } ?? "--",
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.black])
        let unit = NSAttributedString(string: "ms", attributes: [
            .font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.black])
        let numberWidth = ceil(number.size().width)
        let width = 17 + 6 + numberWidth + 2 + ceil(unit.size().width)
        let image = NSImage(size: NSSize(width: width, height: 18), flipped: false) { _ in
            boarImage.draw(in: NSRect(x: 0, y: 0.5, width: 17, height: 17))
            number.draw(at: NSPoint(x: 23, y: 2))
            unit.draw(at: NSPoint(x: 23 + numberWidth + 2, y: 2))
            return true
        }
        image.isTemplate = true
        return image
    }

    static let boarImage: NSImage = {
        let size = NSSize(width: 17, height: 17)
        let image = NSImage(size: size, flipped: true) { bounds in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.setFillColor(NSColor.black.cgColor)
            context.addPath(AresBoarMark().path(in: bounds).cgPath)
            context.drawPath(using: .eoFill)
            return true
        }
        image.isTemplate = true
        return image
    }()
}

/// A compact boar silhouette: broad snout and outward tusks carry the identity.
/// Large negative spaces stay legible at the native 17-point menu-bar size.
private struct AresBoarMark: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x / 32, y: rect.minY + rect.height * y / 32)
        }
        func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(origin: p(x, y), size: CGSize(width: rect.width * w / 32, height: rect.height * h / 32))
        }
        var path = Path()
        // Quiet crown and ears; no cheek spikes or separate brow lines.
        path.move(to: p(3, 3))
        path.addLine(to: p(12, 7))
        path.addQuadCurve(to: p(20, 7), control: p(16, 5))
        path.addLine(to: p(29, 3))
        path.addLine(to: p(27, 13))
        path.addQuadCurve(to: p(26, 21), control: p(28, 17))
        // Tusks belong to the outer silhouette, rather than tiny face cutouts.
        path.addQuadCurve(to: p(30, 16), control: p(29, 20))
        path.addCurve(to: p(23, 27), control1: p(31, 23), control2: p(27, 26))
        path.addQuadCurve(to: p(16, 29), control: p(20, 30))
        path.addQuadCurve(to: p(9, 27), control: p(12, 30))
        path.addCurve(to: p(2, 16), control1: p(5, 26), control2: p(1, 23))
        path.addQuadCurve(to: p(6, 21), control: p(3, 20))
        path.addQuadCurve(to: p(5, 13), control: p(4, 17))
        path.closeSubpath()

        // Two broad eye slits, clear even in a one-color template.
        path.move(to: p(7, 12))
        path.addLine(to: p(13, 14))
        path.addLine(to: p(12, 16))
        path.addLine(to: p(7, 15))
        path.closeSubpath()
        path.move(to: p(25, 12))
        path.addLine(to: p(19, 14))
        path.addLine(to: p(20, 16))
        path.addLine(to: p(25, 15))
        path.closeSubpath()

        // A wide snout, with only two nostrils. No mouth or inner tusk lines.
        path.addRoundedRect(in: box(10, 19, 12, 8), cornerSize: CGSize(width: rect.width * 3 / 32, height: rect.height * 3 / 32))
        path.addEllipse(in: box(12, 21.5, 2.5, 3))
        path.addEllipse(in: box(17.5, 21.5, 2.5, 3))
        return path
    }
}
