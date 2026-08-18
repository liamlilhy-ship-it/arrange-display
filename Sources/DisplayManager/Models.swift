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
    let mode: ModeSpec?
}

/// A display mode described semantically (not by macOS's internal mode id,
/// which can shift across OS updates): pixel resolution, point size
/// (scaling), and refresh rate.
struct ModeSpec: Codable, Hashable {
    let pixelWidth: Int32, pixelHeight: Int32
    let pointWidth: Int32, pointHeight: Int32
    let refreshRate: Double

    /// Refresh matches with tolerance (59.94 vs 60); 0 acts as a wildcard.
    func matches(_ other: ModeSpec) -> Bool {
        pixelWidth == other.pixelWidth && pixelHeight == other.pixelHeight &&
        pointWidth == other.pointWidth && pointHeight == other.pointHeight &&
        (refreshRate == 0 || other.refreshRate == 0 || abs(refreshRate - other.refreshRate) < 0.5)
    }
}

struct Placement: Codable {
    let displayID: CGDirectDisplayID
    let x: Int32
    let y: Int32
    /// Non-nil: configure this display to mirror the given display (origin ignored).
    /// Nil: extended display at (x, y).
    var mirrorOf: CGDirectDisplayID? = nil
    /// Non-nil: also restore this display mode (resolution/scaling/refresh).
    var mode: ModeSpec? = nil
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

/// A profile is a saved screen arrangement. It fits whenever the connected
/// screen counts match (laptop + N externals). Hardware identity is recorded
/// invisibly at capture time and used only as a silent improvement: when the
/// exact monitors are connected, each physical monitor gets its remembered
/// position instead of left-to-right assignment.
struct CustomProfile: Codable, Identifiable {
    var id: UUID
    var name: String
    var displays: [SavedDisplay] // main display implied by origin (0,0)

    /// Snapshot of the current arrangement. Mirror links are stored
    /// structurally (by index) so they survive on any matching hardware.
    static func capture(name: String, displays: [DisplayInfo]) -> CustomProfile {
        let extended = displays.filter { $0.mirrorSourceID == nil }
        let mirrors = displays.filter { $0.mirrorSourceID != nil }
        func saved(_ d: DisplayInfo, mirrorIndex: Int?) -> SavedDisplay {
            SavedDisplay(uuid: d.uuid,
                         x: Int32(d.bounds.origin.x), y: Int32(d.bounds.origin.y),
                         width: Int32(d.bounds.width), height: Int32(d.bounds.height),
                         isBuiltin: d.isBuiltin,
                         mirrorSourceIndex: mirrorIndex,
                         name: d.name,
                         pixelWidth: d.mode?.pixelWidth,
                         pixelHeight: d.mode?.pixelHeight,
                         refreshRate: d.mode?.refreshRate)
        }
        var result = extended.map { saved($0, mirrorIndex: nil) }
        for d in mirrors {
            let sourceIndex = extended.firstIndex { $0.id == d.mirrorSourceID }
            result.append(saved(d, mirrorIndex: sourceIndex))
        }
        return CustomProfile(id: UUID(), name: name, displays: result)
    }

    /// Maps this profile onto the connected displays, or nil when the screen
    /// counts don't fit. Exact-monitor matching is tried first, silently.
    func placements(matching connected: [DisplayInfo]) -> [Placement]? {
        exactPlacements(matching: connected) ?? shapePlacements(matching: connected)
    }

    /// When every saved display carries a hardware UUID and exactly those
    /// monitors are connected, restore each monitor's remembered position.
    private func exactPlacements(matching connected: [DisplayInfo]) -> [Placement]? {
        let byUUID = Dictionary(uniqueKeysWithValues: connected.map { ($0.uuid, $0) })
        let uuids = displays.compactMap(\.uuid)
        guard uuids.count == displays.count,
              displays.count == connected.count,
              Set(uuids) == Set(connected.map(\.uuid)) else { return nil }
        return displays.map { saved in
            let real = byUUID[saved.uuid!]!
            let mirrorOf = saved.mirrorSourceIndex.flatMap { i -> CGDirectDisplayID? in
                displays.indices.contains(i) ? displays[i].uuid.flatMap { byUUID[$0]?.id } : nil
            }
            return Placement(displayID: real.id, x: saved.x, y: saved.y,
                             mirrorOf: mirrorOf, mode: saved.modeSpec)
        }
    }

    /// Role-based fit: counts must match per type (built-in / external,
    /// mirrors included). Extended roles are assigned to real externals
    /// left-to-right, then mirror roles take the remaining monitors.
    /// Positions map proportionally; macOS closes small gaps on apply.
    private func shapePlacements(matching connected: [DisplayInfo]) -> [Placement]? {
        let realBuiltins = connected.filter(\.isBuiltin)
        var realExternals = connected.filter { !$0.isBuiltin }
            .sorted { $0.bounds.minX < $1.bounds.minX }
        guard displays.filter(\.isBuiltin).count == realBuiltins.count,
              displays.filter({ !$0.isBuiltin }).count == realExternals.count,
              !connected.isEmpty else { return nil }

        // Assign each shape role a real display.
        var assignment: [Int: DisplayInfo] = [:]
        var builtins = realBuiltins
        for i in displays.indices where displays[i].isBuiltin {
            assignment[i] = builtins.removeFirst()
        }
        let extendedExternalIdx = displays.indices
            .filter { !displays[$0].isBuiltin && displays[$0].mirrorSourceIndex == nil }
            .sorted {
                displays[$0].y != displays[$1].y
                    ? displays[$0].y < displays[$1].y : displays[$0].x < displays[$1].x
            }
        for i in extendedExternalIdx { assignment[i] = realExternals.removeFirst() }
        for i in displays.indices where !displays[i].isBuiltin && displays[i].mirrorSourceIndex != nil {
            assignment[i] = realExternals.removeFirst()
        }

        // Proportional positions for extended roles.
        let extendedIdx = displays.indices.filter { displays[$0].mirrorSourceIndex == nil }
        let scaleX = extendedIdx.map { CGFloat(assignment[$0]!.bounds.width) }.reduce(0, +)
            / extendedIdx.map { CGFloat(displays[$0].width) }.reduce(0, +)
        let scaleY = extendedIdx.map { CGFloat(assignment[$0]!.bounds.height) }.reduce(0, +)
            / extendedIdx.map { CGFloat(displays[$0].height) }.reduce(0, +)
        var origins: [Int: CGPoint] = [:]
        for i in extendedIdx {
            let shape = displays[i]
            let real = assignment[i]!
            let center = CGPoint(x: (CGFloat(shape.x) + CGFloat(shape.width) / 2) * scaleX,
                                 y: (CGFloat(shape.y) + CGFloat(shape.height) / 2) * scaleY)
            origins[i] = CGPoint(x: center.x - real.bounds.width / 2,
                                 y: center.y - real.bounds.height / 2)
        }
        // The shape's main display (at 0,0) must land at (0,0) to stay main.
        guard let mainIndex = extendedIdx.first(where: { displays[$0].x == 0 && displays[$0].y == 0 }),
              let shift = origins[mainIndex] else { return nil }

        return displays.indices.map { i in
            if let sourceIndex = displays[i].mirrorSourceIndex {
                return Placement(displayID: assignment[i]!.id, x: 0, y: 0,
                                 mirrorOf: assignment[sourceIndex]?.id)
            }
            let origin = origins[i]!
            return Placement(displayID: assignment[i]!.id,
                             x: Int32((origin.x - shift.x).rounded()),
                             y: Int32((origin.y - shift.y).rounded()))
        }
    }
}

struct SavedDisplay: Codable {
    /// Hardware UUID recorded at capture time; invisible metadata used only
    /// for exact-monitor restoration. Nil for screens never tied to hardware.
    let uuid: String?
    let x: Int32, y: Int32
    let width: Int32, height: Int32 // shape/thumbnail geometry
    let isBuiltin: Bool
    /// Structural mirror link: index (into the profile's displays) of the
    /// screen this one mirrors. Nil = extended screen.
    var mirrorSourceIndex: Int? = nil
    /// Legacy files stored the link by hardware UUID; normalized to
    /// mirrorSourceIndex when the store loads.
    var mirrorSourceUUID: String? = nil
    var name: String? = nil // monitor name at capture time
    /// Display mode at capture time; restored only on the exact monitor.
    /// Nil (e.g. in older profiles) = leave the mode alone.
    var pixelWidth: Int32? = nil
    var pixelHeight: Int32? = nil
    var refreshRate: Double? = nil

    var modeSpec: ModeSpec? {
        guard let pixelWidth, let pixelHeight else { return nil }
        return ModeSpec(pixelWidth: pixelWidth, pixelHeight: pixelHeight,
                        pointWidth: width, pointHeight: height,
                        refreshRate: refreshRate ?? 0)
    }
}
