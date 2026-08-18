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
        backfillModes()
    }

    func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([CustomProfile].self, from: data)
        else { return }
        profiles = decoded.map(Self.normalized)
    }

    /// Older files stored mirror links by hardware UUID; convert to the
    /// structural index form.
    private static func normalized(_ profile: CustomProfile) -> CustomProfile {
        var profile = profile
        for i in profile.displays.indices {
            if profile.displays[i].mirrorSourceIndex == nil,
               let uuid = profile.displays[i].mirrorSourceUUID {
                profile.displays[i].mirrorSourceIndex =
                    profile.displays.firstIndex { $0.uuid == uuid && $0.mirrorSourceUUID == nil }
            }
            profile.displays[i].mirrorSourceUUID = nil
        }
        return profile
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

    /// Seeds the three built-in Layouts once, ever — deleting one doesn't
    /// resurrect it. Also migrates away the hardware-pinned preset copies an
    /// earlier version seeded (identified by the old flag + preset names).
    func seedBuiltinLayouts() {
        let defaults = UserDefaults.standard
        if defaults.stringArray(forKey: "seededPresets") != nil {
            let titles = Set(Preset.allCases.map(\.title))
            profiles.removeAll { p in
                titles.contains(p.name) && p.displays.contains { $0.uuid != nil }
            }
            defaults.removeObject(forKey: "seededPresets")
            persist()
        }
        guard !defaults.bool(forKey: "seededLayouts") else { return }
        let layouts = Preset.allCases.map { preset in
            CustomProfile(id: UUID(), name: preset.title,
                          displays: PresetLayouts.genericPlacements(for: preset).map { p in
                              SavedDisplay(uuid: nil,
                                           x: Int32(p.origin.x.rounded()), y: Int32(p.origin.y.rounded()),
                                           width: Int32(p.display.bounds.width),
                                           height: Int32(p.display.bounds.height),
                                           isBuiltin: p.display.isBuiltin)
                          })
        }
        profiles.insert(contentsOf: layouts, at: 0)
        defaults.set(true, forKey: "seededLayouts")
        persist()
    }

    /// Older profiles predate mode memory. When one of their monitors is
    /// connected right now and its current mode has the same point size the
    /// profile already stores, adopt that mode as the remembered one.
    /// Fills only missing fields; never overwrites.
    private func backfillModes() {
        let byUUID = Dictionary(uniqueKeysWithValues:
            DisplayService.currentDisplays().map { ($0.uuid, $0) })
        var changed = false
        for p in profiles.indices {
            for d in profiles[p].displays.indices {
                let saved = profiles[p].displays[d]
                guard saved.pixelWidth == nil, let uuid = saved.uuid,
                      let mode = byUUID[uuid]?.mode,
                      mode.pointWidth == saved.width, mode.pointHeight == saved.height
                else { continue }
                profiles[p].displays[d].pixelWidth = mode.pixelWidth
                profiles[p].displays[d].pixelHeight = mode.pixelHeight
                profiles[p].displays[d].refreshRate = mode.refreshRate
                changed = true
            }
        }
        if changed { persist() }
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

    /// Restores a previously captured ordering (ids in desired order).
    func setOrder(_ ids: [UUID]) {
        let byID = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        profiles = ids.compactMap { byID[$0] } + profiles.filter { !ids.contains($0.id) }
        persist()
    }

    func move(id: UUID, toIndex: Int) {
        guard let from = profiles.firstIndex(where: { $0.id == id }),
              from != toIndex, profiles.indices.contains(toIndex) else { return }
        let profile = profiles.remove(at: from)
        profiles.insert(profile, at: toIndex)
        persist()
    }
}
