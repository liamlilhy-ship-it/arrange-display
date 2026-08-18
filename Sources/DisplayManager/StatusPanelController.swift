import AppKit
import SwiftUI

/// Borderless panel that can still take keyboard focus (name editing).
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Owns the status item and a custom transparent panel in place of
/// MenuBarExtra's window: Tahoe composites a glass backdrop onto system
/// panels at the window-server level, which can't be removed in-process —
/// with our own clear panel, the only background is what the content draws.
@MainActor
final class StatusPanelController: NSObject {
    private let statusItem: NSStatusItem
    private let panel: KeyablePanel
    private var clickMonitor: Any?
    /// Screen y of the panel's top edge; kept fixed when content resizes.
    private var topY: CGFloat = 0

    init(service: DisplayService, store: ProfileStore) {
        let hosting = NSHostingView(rootView: MenuContentView(service: service, store: store))
        hosting.sizingOptions = [.preferredContentSize]

        panel = KeyablePanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 400),
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.transient, .ignoresCycle]
        panel.animationBehavior = .utilityWindow
        panel.contentView = hosting

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        super.init()

        statusItem.button?.image = NSImage(systemSymbolName: "display.2",
                                           accessibilityDescription: "Display Manager")
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggle)

        NotificationCenter.default.addObserver(
            self, selector: #selector(panelDidResize),
            name: NSWindow.didResizeNotification, object: panel)

        // Debug: DM_OPEN_PANEL=1 auto-opens the panel after launch so the
        // design can be screenshotted without a manual click.
        if ProcessInfo.processInfo.environment["DM_OPEN_PANEL"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.open() }
        }
    }

    @objc private func toggle() {
        panel.isVisible ? close() : open()
    }

    private func open() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let size = panel.contentView?.fittingSize ?? panel.frame.size
        topY = buttonFrame.minY - 6

        var x = buttonFrame.midX - size.width / 2
        if let screen = buttonWindow.screen {
            x = min(max(x, screen.visibleFrame.minX + 8),
                    screen.visibleFrame.maxX - size.width - 8)
        }
        panel.setFrame(NSRect(x: x, y: topY - size.height,
                              width: size.width, height: size.height), display: true)
        panel.makeKeyAndOrderFront(nil)

        clickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
    }

    private func close() {
        panel.orderOut(nil)
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
    }

    /// Content growth (e.g. the name editor) resizes the window; keep the
    /// top edge anchored under the menu bar instead of growing upward.
    @objc private func panelDidResize() {
        guard panel.isVisible else { return }
        var frame = panel.frame
        frame.origin.y = topY - frame.height
        panel.setFrameOrigin(frame.origin)
        panel.invalidateShadow()
    }
}
