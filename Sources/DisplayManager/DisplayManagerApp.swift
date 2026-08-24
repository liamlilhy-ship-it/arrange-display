import SwiftUI

struct DisplayManagerApp: App {
    init() {
        let service = DisplayService()
        let store = ProfileStore()
        store.seedBuiltinLayouts()
        _service = StateObject(wrappedValue: service)
        _store = StateObject(wrappedValue: store)
        hotkeys = HotkeyManager(store: store, service: service)
        // Keep the login-item registration in step with the setting
        // (on by default) every launch. Also repairs the registration after
        // an update replaces the bundle.
        LoginItem.sync(
            enabled: UserDefaults.standard.object(forKey: "launchAtLogin") as? Bool ?? true)
        Updater.start()

        // Debug: DM_CHECK_UPDATES=1 runs a user-initiated update check on
        // launch, so the "up to date" and failure dialogs can be seen without
        // clicking. Background checks never show errors, so this is the only
        // way to exercise that path.
        if ProcessInfo.processInfo.environment["DM_CHECK_UPDATES"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                Updater.checkNow()
            }
        }

        // Debug: DM_HOTKEY_TOAST=<text> shows the hotkey toast on launch,
        // so it can be screenshotted without pressing a hotkey.
        if let text = ProcessInfo.processInfo.environment["DM_HOTKEY_TOAST"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                HotkeyToast.show(text)
            }
        }

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

    @StateObject private var service: DisplayService
    @StateObject private var store: ProfileStore
    // Global ⌃⌘1–9 preset hotkeys, alive for the app's lifetime.
    private let hotkeys: HotkeyManager

    var body: some Scene {
        MenuBarExtra("Display Manager", systemImage: "display.2") {
            MenuContentView(service: service, store: store)
        }
        .menuBarExtraStyle(.window)
    }
}
