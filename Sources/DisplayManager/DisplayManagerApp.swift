import SwiftUI

struct DisplayManagerApp: App {
    init() {
        // Debug: DM_OPEN_PANEL=1 auto-opens the menu bar panel after launch
        // so the design can be screenshotted without a manual click.
        if ProcessInfo.processInfo.environment["DM_OPEN_PANEL"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                func statusButton(in view: NSView) -> NSStatusBarButton? {
                    if let b = view as? NSStatusBarButton { return b }
                    for sub in view.subviews {
                        if let b = statusButton(in: sub) { return b }
                    }
                    return nil
                }
                for window in NSApp.windows
                where String(describing: type(of: window)).contains("StatusBarWindow") {
                    if let content = window.contentView,
                       let button = statusButton(in: content) {
                        button.performClick(nil)
                    }
                }
            }
        }
    }

    @StateObject private var service = DisplayService()
    @StateObject private var store = {
        let store = ProfileStore()
        store.seedBuiltinLayouts()
        return store
    }()

    var body: some Scene {
        MenuBarExtra("Display Manager", systemImage: "display.2") {
            MenuContentView(service: service, store: store)
        }
        .menuBarExtraStyle(.window)
    }
}
