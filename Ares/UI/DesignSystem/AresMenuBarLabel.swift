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

/// Front-facing ears, angular brow, long snout and paired tusks taken from
/// Ares's app icon. Details are reduced to negative space for menu-bar sizes.
private struct AresBoarMark: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x / 32, y: rect.minY + rect.height * y / 32)
        }
        var path = Path()
        path.move(to: p(2, 2))
        path.addLine(to: p(10, 5))
        path.addLine(to: p(12, 7))
        path.addLine(to: p(16, 4))
        path.addLine(to: p(20, 7))
        path.addLine(to: p(22, 5))
        path.addLine(to: p(30, 2))
        path.addLine(to: p(28.5, 10))
        path.addLine(to: p(25, 13))
        path.addLine(to: p(28, 20))
        path.addLine(to: p(26, 19))
        path.addCurve(to: p(16, 30), control1: p(26, 24), control2: p(21, 27))
        path.addCurve(to: p(6, 19), control1: p(11, 27), control2: p(6, 24))
        path.addLine(to: p(4, 20))
        path.addLine(to: p(7, 13))
        path.addLine(to: p(3.5, 10))
        path.closeSubpath()

        // Angled eyes, matching the original icon's forward-facing expression.
        path.move(to: p(7, 10.5))
        path.addLine(to: p(13.5, 14.5))
        path.addLine(to: p(8, 14.5))
        path.closeSubpath()
        path.move(to: p(25, 10.5))
        path.addLine(to: p(18.5, 14.5))
        path.addLine(to: p(24, 14.5))
        path.closeSubpath()

        // One clean negative-space tusk on each side of the muzzle.
        path.move(to: p(7.5, 16))
        path.addCurve(to: p(12.5, 23.5), control1: p(7.5, 21), control2: p(10, 23))
        path.addLine(to: p(12, 18))
        path.closeSubpath()
        path.move(to: p(24.5, 16))
        path.addCurve(to: p(19.5, 23.5), control1: p(24.5, 21), control2: p(22, 23))
        path.addLine(to: p(20, 18))
        path.closeSubpath()

        // A single oval nose keeps the lower face quiet at small sizes.
        path.addEllipse(in: CGRect(x: p(14, 24).x, y: p(14, 24).y, width: rect.width * 4 / 32, height: rect.height * 2 / 32))
        path.closeSubpath()
        return path
    }
}
