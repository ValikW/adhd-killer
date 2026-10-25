import AppKit
import ApplicationServices
import CoreGraphics

@MainActor
final class FocusObserver {
    var onActivate: (() -> Void)?
    private var locked = false
    private var prompted = false

    init() {
        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(self, selector: #selector(screenLocked),
                                name: Notification.Name("com.apple.screenIsLocked"), object: nil)
        distributed.addObserver(self, selector: #selector(screenUnlocked),
                                name: Notification.Name("com.apple.screenIsUnlocked"), object: nil)
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(screenLocked),
                              name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(screenUnlocked),
                              name: NSWorkspace.screensDidWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(activated),
                              name: NSWorkspace.didActivateApplicationNotification, object: nil)
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    func promptForPermission() {
        guard !prompted else { return }
        prompted = true
        let option = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([option: true] as CFDictionary)
    }

    func observe() -> (context: FocusContext?, idleSeconds: Double, locked: Bool, permitted: Bool) {
        let permitted = AXIsProcessTrusted()
        let idle = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState, eventType: CGEventType(rawValue: UInt32.max)!)
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return (nil, idle, locked, permitted)
        }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var windowValue: CFTypeRef?
        var title: String?
        var url: String?
        if permitted,
           AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString,
                                         &windowValue) == .success,
           let windowValue {
            let window = windowValue as! AXUIElement
            var titleValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString,
                                             &titleValue) == .success {
                title = (titleValue as? String).flatMap { $0.isEmpty ? nil : $0 }
            }
            if FocusCore.browserBundleIDs.contains(app.bundleIdentifier ?? "") {
                var documentValue: CFTypeRef?
                if AXUIElementCopyAttributeValue(window, kAXDocumentAttribute as CFString,
                                                 &documentValue) == .success {
                    url = FocusCore.normalizeURL(documentValue as? String)
                }
            }
        }
        let context = FocusContext(appName: app.localizedName ?? "",
                                   bundleID: app.bundleIdentifier ?? "",
                                   windowTitle: title, url: url)
        return (context, idle, locked, permitted)
    }

    @objc private func screenLocked() { locked = true; onActivate?() }
    @objc private func screenUnlocked() { locked = false; onActivate?() }
    @objc private func activated() { onActivate?() }
}
