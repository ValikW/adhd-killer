import AppKit

private final class CharacterView: NSView {
    var menuForClick: NSMenu?

    override func mouseDown(with event: NSEvent) {
        guard let menuForClick else { return }
        NSMenu.popUpContextMenu(menuForClick, with: event, for: self)
    }
}

@MainActor
final class FocusCharacter: NSObject {
    var onThisIsWork: () -> Void = {}
    var onSnooze: () -> Void = {}
    var onCloseTask: () -> Void = {}
    var onDisable: () -> Void = {}

    private let panel: NSPanel
    private let container = CharacterView(frame: NSRect(x: 0, y: 0, width: 280, height: 100))
    private let icon = NSImageView(frame: NSRect(x: 14, y: 26, width: 48, height: 48))
    private let message = NSTextField(wrappingLabelWithString: "")
    private var alarm: Alarm = .none

    override init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 280, height: 100),
                        styleMask: [.nonactivatingPanel, .borderless],
                        backing: .buffered, defer: false)
        super.init()
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = container
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.95).cgColor
        icon.imageScaling = .scaleProportionallyUpOrDown
        container.addSubview(icon)
        message.frame = NSRect(x: 74, y: 12, width: 190, height: 76)
        message.font = .systemFont(ofSize: 14, weight: .medium)
        message.maximumNumberOfLines = 2
        container.addSubview(message)
    }

    func show(_ alarm: Alarm, line: String, shortTask: String) {
        guard alarm != .none else { self.alarm = .none; panel.orderOut(nil); return }
        self.alarm = alarm
        let symbol = alarm == .hard ? "flame.fill" : "eye"
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: L.t("Надзор", "Focus guard"))
            ?? NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: L.t("Надзор", "Focus guard"))
        icon.contentTintColor = alarm == .hard ? .systemRed : .systemOrange
        container.layer?.borderWidth = alarm == .hard ? 1 : 0
        container.layer?.borderColor = NSColor.systemRed.cgColor
        message.stringValue = line.isEmpty
            ? (alarm == .hard ? L.t("Давно не по делу. Возвращаемся.", "Off task for a while. Back to work.")
                              : L.t("Задача: «\(shortTask)». Это не она.", "Task: “\(shortTask)”. This isn’t it."))
            : line
        let menu = NSMenu()
        add(L.t("Это работа", "This is work"), #selector(thisIsWork), to: menu)
        add(L.t("Перерыв 15 мин", "Break 15 min"), #selector(snooze), to: menu)
        add(L.t("Задача сделана", "Task done"), #selector(closeTask), to: menu)
        add(L.t("Выключить надзор", "Turn off guard"), #selector(disable), to: menu)
        container.menuForClick = menu
        if let screen = NSScreen.main {
            panel.setFrameOrigin(NSPoint(x: screen.frame.maxX - 304,
                                         y: screen.frame.minY + 24))
        }
        panel.orderFrontRegardless()
    }

    private func add(_ title: String, _ selector: Selector, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }

    @objc private func thisIsWork() { onThisIsWork() }
    @objc private func snooze() { onSnooze() }
    @objc private func closeTask() { onCloseTask() }
    @objc private func disable() { onDisable() }
}
