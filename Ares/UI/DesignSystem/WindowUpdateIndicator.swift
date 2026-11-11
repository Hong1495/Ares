import AppKit
import SwiftUI

/// Pure window chrome. No updater, network or production service dependencies.
struct WindowUpdateIndicator: NSViewRepresentable {
    var version: String?
    var action: () -> Void

    func makeNSView(context: Context) -> UpdateIndicatorAnchor { UpdateIndicatorAnchor() }
    func updateNSView(_ view: UpdateIndicatorAnchor, context: Context) {
        view.version = version
        view.action = action
        view.scheduleLayout()
    }
    static func dismantleNSView(_ view: UpdateIndicatorAnchor, coordinator: ()) { view.detach() }
}

final class UpdateIndicatorAnchor: NSView {
    var version: String?
    var action: (() -> Void)?
    private let button = UpdateDotButton(frame: .zero)
    private var observations: [NSObjectProtocol] = []

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        detach()
        guard let window else { return }
        for name in [NSWindow.didResizeNotification, NSWindow.didEnterFullScreenNotification,
                     NSWindow.didExitFullScreenNotification, NSWindow.didBecomeKeyNotification] {
            observations.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleLayout() }
            })
        }
        button.target = self
        button.action = #selector(openUpdate)
        scheduleLayout()
    }

    override func layout() { super.layout(); scheduleLayout() }

    func detach() {
        observations.forEach(NotificationCenter.default.removeObserver)
        observations.removeAll()
        button.removeFromSuperview()
    }

    func scheduleLayout() {
        DispatchQueue.main.async { [weak self] in self?.positionButton() }
    }

    private func positionButton() {
        guard version != nil, let window, !window.styleMask.contains(.fullScreen),
              let green = window.standardWindowButton(.zoomButton),
              let yellow = window.standardWindowButton(.miniaturizeButton),
              let container = green.superview, !green.isHidden else {
            button.removeFromSuperview()
            return
        }
        // Same rule as Bee: use native geometry, preserving the green→yellow center spacing.
        let g = green.convert(green.bounds, to: container)
        let y = yellow.convert(yellow.bounds, to: container)
        button.frame = NSRect(x: g.minX + (g.midX - y.midX), y: g.minY, width: g.width, height: g.height)
        button.toolTip = "Ares \(version ?? "") — Update available"
        button.setAccessibilityLabel("Update Ares to \(version ?? "")")
        if button.superview !== container { container.addSubview(button) }
        button.needsDisplay = true
    }

    @objc private func openUpdate() { action?() }
}

private final class UpdateDotButton: NSButton {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        title = ""
        setButtonType(.momentaryChange)
        focusRingType = .exterior
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        let circle = bounds.insetBy(dx: 0.5, dy: 0.5)
        (isHighlighted ? NSColor(red: 1, green: 0.68, blue: 0.33, alpha: 1) : NSColor(red: 1, green: 0.59, blue: 0.23, alpha: 1)).setFill()
        NSBezierPath(ovalIn: circle).fill()
        NSColor(red: 0.43, green: 0.20, blue: 0.02, alpha: 0.9).setStroke()
        let arrow = NSBezierPath()
        arrow.lineWidth = 1.1
        arrow.lineCapStyle = .round
        arrow.lineJoinStyle = .round
        let x = bounds.midX, y = bounds.midY
        let direction: CGFloat = isFlipped ? -1 : 1
        arrow.move(to: NSPoint(x: x, y: y + 3 * direction))
        arrow.line(to: NSPoint(x: x, y: y - 2.5 * direction))
        arrow.move(to: NSPoint(x: x - 2.2, y: y - 0.3 * direction))
        arrow.line(to: NSPoint(x: x, y: y - 2.5 * direction))
        arrow.line(to: NSPoint(x: x + 2.2, y: y - 0.3 * direction))
        arrow.stroke()
    }
}
