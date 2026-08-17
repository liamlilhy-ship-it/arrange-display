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

    /// Materializes each built-in preset into a regular saved profile the
    /// first time the connected displays match its shape, so preset rows and
    /// user-saved rows behave identically. Seeds once per preset, ever —
    /// deleting a seeded profile doesn't resurrect it.
    private static let seededKey = "seededPresets"

    func seedPresets(from displays: [DisplayInfo]) {
        var seeded = Set(UserDefaults.standard.stringArray(forKey: Self.seededKey) ?? [])
        var changed = false
        for preset in Preset.allCases.reversed() {
            guard !seeded.contains(preset.rawValue),
                  let placements = PresetLayouts.placements(for: preset, displays: displays)
            else { continue }
            let savedDisplays = placements.map { p in
                SavedDisplay(uuid: p.display.uuid,
                             x: Int32(p.origin.x.rounded()), y: Int32(p.origin.y.rounded()),
                             width: Int32(p.display.bounds.width), height: Int32(p.display.bounds.height),
                             isBuiltin: p.display.isBuiltin,
                             mirrorSourceUUID: nil)
            }
            profiles.insert(CustomProfile(id: UUID(), name: preset.title, displays: savedDisplays), at: 0)
            seeded.insert(preset.rawValue)
            changed = true
        }
        if changed {
            UserDefaults.standard.set(Array(seeded), forKey: Self.seededKey)
            persist()
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
