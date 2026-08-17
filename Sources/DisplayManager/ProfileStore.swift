import Foundation

final class ProfileStore: ObservableObject {
    @Published private(set) var profiles: [CustomProfile] = []

    private let url: URL

    init(url: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("DisplayManager/profiles.json")
    ) {
        self.url = url
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([CustomProfile].self, from: data)
        else { return }
        profiles = decoded
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(profiles).write(to: url)
        } catch {
            NSLog("DisplayManager: failed to save profiles: \(error)")
        }
    }

    func add(_ profile: CustomProfile) {
        profiles.append(profile)
        persist()
    }

    func update(id: UUID, displays: [SavedDisplay]) {
        guard let i = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[i].displays = displays
        persist()
    }

    func rename(id: UUID, to name: String) {
        guard let i = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[i].name = name
        persist()
    }

    func delete(id: UUID) {
        profiles.removeAll { $0.id == id }
        persist()
    }
}
