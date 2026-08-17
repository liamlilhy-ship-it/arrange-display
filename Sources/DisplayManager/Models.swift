import CoreGraphics
import Foundation

struct DisplayInfo: Identifiable, Hashable {
    let id: CGDirectDisplayID
    let uuid: String
    let name: String
    let bounds: CGRect
    let isBuiltin: Bool
    let isMain: Bool
    /// Non-nil when this display mirrors another; the value is the mirrored (source) display.
    let mirrorSourceID: CGDirectDisplayID?
}

struct Placement: Codable {
    let displayID: CGDirectDisplayID
    let x: Int32
    let y: Int32
    /// Non-nil: configure this display to mirror the given display (origin ignored).
    /// Nil: extended display at (x, y).
    var mirrorOf: CGDirectDisplayID? = nil
}

enum Preset: String, CaseIterable, Identifiable {
    case externalAboveBuiltin = "a"
    case dualExternalBuiltinRight = "b"
    case dualExternalBuiltinBottom = "c"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .externalAboveBuiltin: return "External above, built-in below"
        case .dualExternalBuiltinRight: return "Dual external, built-in right"
        case .dualExternalBuiltinBottom: return "Dual external, built-in bottom"
        }
    }

    var requiredExternalCount: Int {
        switch self {
        case .externalAboveBuiltin: return 1
        case .dualExternalBuiltinRight, .dualExternalBuiltinBottom: return 2
        }
    }
}

struct CustomProfile: Codable, Identifiable {
    var id: UUID
    var name: String
    var displays: [SavedDisplay] // main display implied by origin (0,0)

    /// Snapshot of the current arrangement, keyed by display hardware UUID.
    static func capture(name: String, displays: [DisplayInfo]) -> CustomProfile {
        let byID = Dictionary(uniqueKeysWithValues: displays.map { ($0.id, $0) })
        return CustomProfile(id: UUID(), name: name, displays: displays.map { d in
            SavedDisplay(
                uuid: d.uuid,
                x: Int32(d.bounds.origin.x), y: Int32(d.bounds.origin.y),
                width: Int32(d.bounds.width), height: Int32(d.bounds.height),
                isBuiltin: d.isBuiltin,
                mirrorSourceUUID: d.mirrorSourceID.flatMap { byID[$0]?.uuid }
            )
        })
    }

    var hasMirroring: Bool { displays.contains { $0.mirrorSourceUUID != nil } }

    /// Maps saved displays to the connected ones by hardware UUID.
    /// Returns nil unless the connected display set exactly matches the saved set.
    func placements(matching connected: [DisplayInfo]) -> [Placement]? {
        let byUUID = Dictionary(uniqueKeysWithValues: connected.map { ($0.uuid, $0) })
        guard Set(displays.map(\.uuid)) == Set(connected.map(\.uuid)) else { return nil }
        return displays.map { saved in
            Placement(displayID: byUUID[saved.uuid]!.id,
                      x: saved.x, y: saved.y,
                      mirrorOf: saved.mirrorSourceUUID.flatMap { byUUID[$0]?.id })
        }
    }
}

struct SavedDisplay: Codable {
    let uuid: String // pin-by-identity: this physical display, wherever it's plugged in
    let x: Int32, y: Int32
    let width: Int32, height: Int32 // for thumbnail rendering
    let isBuiltin: Bool
    let mirrorSourceUUID: String? // non-nil when this display mirrors another
}
