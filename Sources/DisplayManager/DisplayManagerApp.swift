import SwiftUI

struct DisplayManagerApp: App {
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
