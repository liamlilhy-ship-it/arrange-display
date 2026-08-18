import CoreGraphics

/// A display and the origin (in global points) a preset wants for it.
/// Origins are laid out so the intended main display sits at (0,0),
/// which is what makes macOS treat it as main.
typealias PresetPlacement = (display: DisplayInfo, origin: CGPoint)

enum PresetLayouts {
    /// Computes placements for a preset from the actual connected displays.
    /// Returns nil when the connected-display shape doesn't match the preset
    /// (wrong number of externals, or no built-in display).
    static func placements(for preset: Preset, displays: [DisplayInfo]) -> [PresetPlacement]? {
        guard let builtin = displays.first(where: { $0.isBuiltin }) else { return nil }
        // Left-to-right by current position, so the profile keeps whichever
        // monitor is currently on the left as "left".
        let externals = displays.filter { !$0.isBuiltin }.sorted { $0.bounds.minX < $1.bounds.minX }
        guard externals.count == preset.requiredExternalCount else { return nil }

        switch preset {
        case .externalAboveBuiltin:
            let ext = externals[0]
            return [
                (ext, .zero),
                (builtin, CGPoint(x: (ext.bounds.width - builtin.bounds.width) / 2,
                                  y: ext.bounds.height)),
            ]
        case .dualExternalBuiltinRight:
            let (left, right) = (externals[0], externals[1])
            return [
                (left, .zero),
                (right, CGPoint(x: left.bounds.width, y: 0)),
                (builtin, CGPoint(x: left.bounds.width + right.bounds.width,
                                  y: right.bounds.height - builtin.bounds.height)),
            ]
        case .dualExternalBuiltinBottom:
            let (left, right) = (externals[0], externals[1])
            let rowBottom = max(left.bounds.height, right.bounds.height)
            return [
                (left, .zero),
                (right, CGPoint(x: left.bounds.width, y: 0)),
                (builtin, CGPoint(x: (left.bounds.width + right.bounds.width - builtin.bounds.width) / 2,
                                  y: rowBottom)),
            ]
        }
    }

    /// Placements rendered from generic display sizes, used for thumbnails
    /// when the real setup doesn't match the preset.
    static func genericPlacements(for preset: Preset) -> [PresetPlacement] {
        func fake(_ id: CGDirectDisplayID, w: CGFloat, h: CGFloat, builtin: Bool) -> DisplayInfo {
            DisplayInfo(id: id, uuid: "", name: "", bounds: CGRect(x: 0, y: 0, width: w, height: h),
                        isBuiltin: builtin, isMain: false, mirrorSourceID: nil, mode: nil)
        }
        let displays = [fake(1, w: 1920, h: 1080, builtin: false),
                        fake(2, w: 1920, h: 1080, builtin: false),
                        fake(3, w: 1470, h: 956, builtin: true)]
        let subset = Array(displays.prefix(preset.requiredExternalCount)) + [displays[2]]
        return placements(for: preset, displays: subset)!
    }
}
