import SwiftUI

struct DisplayManagerApp: App {
    @StateObject private var service = DisplayService()

    var body: some Scene {
        MenuBarExtra("Display Manager", systemImage: "display.2") {
            MenuContentView(service: service)
        }
        .menuBarExtraStyle(.window)
    }
}
