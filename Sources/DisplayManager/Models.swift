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

/// A profile is a saved screen arrangement. Its one option is monitor
/// memory: when the displays carry hardware UUIDs the profile applies only
/// to those exact monitors (and can mirror); without UUIDs it is a shape
/// that fits any monitors matching its screen counts.
struct CustomProfile: Codable, Identifiable {
    var id: UUID
    var name: String
    var displays: [SavedDisplay] // main display implied by origin (0,0)

    var remembersMonitors: Bool { displays.contains { $0.uuid != nil } }

    /// Snapshot of the current arrangement, keyed by display hardware UUID.
    static func capture(name: String, displays: [DisplayInfo]) -> CustomProfile {
        let byID = Dictionary(uniqueKeysWithValues: displays.map { ($0.id, $0) })
        return CustomProfile(id: UUID(), name: name, displays: displays.map { d in
            SavedDisplay(
                uuid: d.uuid,
                x: Int32(d.bounds.origin.x), y: Int32(d.bounds.origin.y),
                width: Int32(d.bounds.width), height: Int32(d.bounds.height),
                isBuiltin: d.isBuiltin,
                mirrorSourceUUID: d.mirrorSourceID.flatMap { byID[$0]?.uuid },
                name: d.name
            )
        })
    }

    /// Maps this profile onto the connected displays, or nil when it doesn't fit.
    func placements(matching connected: [DisplayInfo]) -> [Placement]? {
        remembersMonitors ? setupPlacements(matching: connected) : layoutPlacements(matching: connected)
    }

    /// Setup: exact hardware-UUID match, both directions.
    private func setupPlacements(matching connected: [DisplayInfo]) -> [Placement]? {
        let byUUID = Dictionary(uniqueKeysWithValues: connected.map { ($0.uuid, $0) })
        guard Set(displays.compactMap(\.uuid)) == Set(connected.map(\.uuid)),
              displays.count == connected.count else { return nil }
        return displays.compactMap { saved in
            guard let uuid = saved.uuid, let real = byUUID[uuid] else { return nil }
            return Placement(displayID: real.id,
                             x: saved.x, y: saved.y,
                             mirrorOf: saved.mirrorSourceUUID.flatMap { byUUID[$0]?.id })
        }
    }

    /// Layout: fits when the built-in/external counts match. Shape roles are
    /// assigned to real externals left-to-right; positions map proportionally
    /// (macOS closes any small gaps/overlaps when the arrangement is applied).
    private func layoutPlacements(matching connected: [DisplayInfo]) -> [Placement]? {
        let shapeBuiltins = displays.filter(\.isBuiltin)
        let shapeExternals = displays.filter { !$0.isBuiltin }
            .sorted { $0.y != $1.y ? $0.y < $1.y : $0.x < $1.x }
        let realBuiltins = connected.filter(\.isBuiltin)
        let realExternals = connected.filter { !$0.isBuiltin }
            .sorted { $0.bounds.minX < $1.bounds.minX }
        guard shapeBuiltins.count == realBuiltins.count,
              shapeExternals.count == realExternals.count,
              !connected.isEmpty else { return nil }

        let pairs = Array(zip(shapeBuiltins + shapeExternals, realBuiltins + realExternals))
        let scaleX = pairs.map { CGFloat($0.1.bounds.width) }.reduce(0, +)
            / pairs.map { CGFloat($0.0.width) }.reduce(0, +)
        let scaleY = pairs.map { CGFloat($0.1.bounds.height) }.reduce(0, +)
            / pairs.map { CGFloat($0.0.height) }.reduce(0, +)

        var origins: [(DisplayInfo, CGPoint)] = pairs.map { shape, real in
            let center = CGPoint(x: (CGFloat(shape.x) + CGFloat(shape.width) / 2) * scaleX,
                                 y: (CGFloat(shape.y) + CGFloat(shape.height) / 2) * scaleY)
            return (real, CGPoint(x: center.x - real.bounds.width / 2,
                                  y: center.y - real.bounds.height / 2))
        }
        // The shape's main display (at 0,0) must land at (0,0) to stay main.
        guard let mainIndex = pairs.firstIndex(where: { $0.0.x == 0 && $0.0.y == 0 })
        else { return nil }
        let shift = origins[mainIndex].1
        origins = origins.map { ($0.0, CGPoint(x: $0.1.x - shift.x, y: $0.1.y - shift.y)) }

        return origins.map {
            Placement(displayID: $0.0.id, x: Int32($0.1.x.rounded()), y: Int32($0.1.y.rounded()))
        }
    }
}

struct SavedDisplay: Codable {
    /// Hardware UUID pinning this to a physical monitor; nil when the
    /// profile doesn't remember monitors and the display is a role filled
    /// by whatever monitor is connected.
    let uuid: String?
    let x: Int32, y: Int32
    let width: Int32, height: Int32 // shape/thumbnail geometry
    let isBuiltin: Bool
    let mirrorSourceUUID: String? // non-nil when this display mirrors another
    var name: String? = nil // monitor name at capture time (Setups)
}
