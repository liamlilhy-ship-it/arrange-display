import SwiftUI

/// The status item and panel are AppKit-managed (StatusPanelController) —
/// MenuBarExtra's system panel carries a window-server glass backdrop that
/// can't be made fully transparent.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: StatusPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = ProfileStore()
        store.seedBuiltinLayouts()
        controller = StatusPanelController(service: DisplayService(), store: store)
    }
}

struct DisplayManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
