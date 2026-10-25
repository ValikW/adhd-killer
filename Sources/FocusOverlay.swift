import AppKit

@MainActor
final class FocusOverlay: NSObject {
    private var windows: [NSWindow] = []
    private var alarm: Alarm = .none

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        rebuild()
    }

    func show(_ alarm: Alarm) {
        guard self.alarm != alarm else { return }
        self.alarm = alarm
        for window in windows { update(window) }
    }

    @objc private func screensChanged() { rebuild() }

    private func rebuild() {
        windows.forEach { $0.orderOut(nil); $0.close() }
        windows = NSScreen.screens.map { screen in
            let window = NSWindow(contentRect: screen.frame, styleMask: .borderless,
                                  backing: .buffered, defer: false, screen: screen)
            window.isReleasedWhenClosed = false
            window.level = .screenSaver
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .stationary,
                                         .fullScreenAuxiliary, .ignoresCycle]
            let border = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
            border.wantsLayer = true
            if let layer = border.layer {
                let width = min(85, min(screen.frame.width, screen.frame.height) / 8)
                let red = NSColor.systemRed.withAlphaComponent(0.85).cgColor
                let clear = NSColor.systemRed.withAlphaComponent(0).cgColor
                let edges: [(CGRect, [CGColor], CGPoint, CGPoint)] = [
                    (CGRect(x: 0, y: 0, width: width, height: screen.frame.height),
                     [red, clear], CGPoint(x: 0, y: 0.5), CGPoint(x: 1, y: 0.5)),
                    (CGRect(x: screen.frame.width - width, y: 0, width: width, height: screen.frame.height),
                     [clear, red], CGPoint(x: 0, y: 0.5), CGPoint(x: 1, y: 0.5)),
                    (CGRect(x: 0, y: 0, width: screen.frame.width, height: width),
                     [red, clear], CGPoint(x: 0.5, y: 0), CGPoint(x: 0.5, y: 1)),
                    (CGRect(x: 0, y: screen.frame.height - width, width: screen.frame.width, height: width),
                     [clear, red], CGPoint(x: 0.5, y: 0), CGPoint(x: 0.5, y: 1)),
                ]
                for (frame, colors, start, end) in edges {
                    let glow = CAGradientLayer()
                    glow.frame = frame
                    glow.colors = colors
                    glow.startPoint = start
                    glow.endPoint = end
                    layer.addSublayer(glow)
                }
            }
            window.contentView = border
            update(window)
            return window
        }
    }

    private func update(_ window: NSWindow) {
        guard let layer = window.contentView?.layer else { return }
        layer.removeAnimation(forKey: "focusPulse")
        switch alarm {
        case .none:
            window.orderOut(nil)
        case .soft:
            layer.opacity = 0.8
            pulse(layer, from: 0.25, to: 0.9, duration: 1.2)
            window.orderFrontRegardless()
        case .hard:
            layer.opacity = 1
            pulse(layer, from: 0.35, to: 1, duration: 0.55)
            window.orderFrontRegardless()
        }
    }

    private func pulse(_ layer: CALayer, from low: Float, to high: Float, duration: TimeInterval) {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = low
        animation.toValue = high
        animation.duration = duration
        animation.autoreverses = true
        animation.repeatCount = .infinity
        layer.add(animation, forKey: "focusPulse")
    }
}
