import SwiftUI
import AppKit

/// Template artwork lets macOS choose its menu-bar tint independently of the
/// app's theme, including wallpaper-driven appearance and selection highlighting.
struct AresMenuBarLabel: View {
    var showsLatency: Bool
    var latency: Int?

    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: Self.boarImage)
                .renderingMode(.template)
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)

            if showsLatency {
                Text(latency.map { $0 > 0 ? "\($0)" : "--" } ?? "--")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .fixedSize()
            }
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ares")
        .accessibilityValue(showsLatency ? latencyDescription : "")
    }

    private var latencyDescription: String {
        guard let latency else { return "Latency not measured" }
        return latency > 0 ? "\(latency) milliseconds" : "Node unavailable"
    }

    static let boarImage: NSImage = {
        let size = NSSize(width: 20, height: 20)
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
        path.move(to: p(8, 11))
        path.addLine(to: p(13, 14))
        path.addLine(to: p(9, 14))
        path.closeSubpath()
        path.move(to: p(24, 11))
        path.addLine(to: p(19, 14))
        path.addLine(to: p(23, 14))
        path.closeSubpath()

        // One clean negative-space tusk on each side of the muzzle.
        path.move(to: p(9.3, 16.5))
        path.addCurve(to: p(12.3, 22), control1: p(9.5, 20), control2: p(10, 21))
        path.addLine(to: p(12, 17.5))
        path.closeSubpath()
        path.move(to: p(22.7, 16.5))
        path.addCurve(to: p(19.7, 22), control1: p(22.5, 20), control2: p(22, 21))
        path.addLine(to: p(20, 17.5))
        path.closeSubpath()

        // A single oval nose keeps the lower face quiet at small sizes.
        path.addEllipse(in: CGRect(x: p(13.5, 22).x, y: p(13.5, 22).y, width: rect.width * 5 / 32, height: rect.height * 3 / 32))
        path.closeSubpath()
        return path
    }
}
