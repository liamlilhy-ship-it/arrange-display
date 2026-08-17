import SwiftUI

struct DisplayManagerApp: App {
    @StateObject private var service = DisplayService()
    @StateObject private var store = ProfileStore()

    var body: some Scene {
        MenuBarExtra("Display Manager", systemImage: "display.2") {
            MenuContentView(service: service, store: store)
        }
        .menuBarExtraStyle(.window)

        WindowGroup("Edit Arrangement", id: "profile-editor", for: UUID.self) { $profileID in
            ProfileEditorView(store: store, profileID: profileID)
        }
        .defaultSize(width: 560, height: 420)
    }
}
