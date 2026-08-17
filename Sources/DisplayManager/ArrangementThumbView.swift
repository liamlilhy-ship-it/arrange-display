import SwiftUI

/// Miniature drawing of an arrangement: externals as plain rounded rects,
/// the built-in display as a rect with a laptop base bar underneath.
/// Shows a mirror badge when the arrangement contains mirrored displays.
struct ArrangementThumbView: View {
    let placements: [PresetPlacement]
    var showMirrorBadge: Bool = false

    /// Placements reconstructed from a saved profile's geometry.
    /// Mirrored displays overlap their source, so only extended ones are drawn.
    init(profile: CustomProfile) {
        placements = profile.displays.filter { $0.mirrorSourceUUID == nil }
            .enumerated().map { i, d in
                let info = DisplayInfo(
                    id: CGDirectDisplayID(i), uuid: d.uuid, name: "",
                    bounds: CGRect(x: 0, y: 0, width: CGFloat(d.width), height: CGFloat(d.height)),
                    isBuiltin: d.isBuiltin, isMain: false, mirrorSourceID: nil)
                return (info, CGPoint(x: CGFloat(d.x), y: CGFloat(d.y)))
            }
        showMirrorBadge = profile.hasMirroring
    }

    init(placements: [PresetPlacement]) {
        self.placements = placements
    }

    private static let baseBarHeight: CGFloat = 90 // in display-point space

    var body: some View {
        Canvas { context, size in
            let rects = placements.map { placement -> (CGRect, Bool) in
                var r = CGRect(origin: placement.origin, size: placement.display.bounds.size)
                if placement.display.isBuiltin { r.size.height += Self.baseBarHeight }
                return (r, placement.display.isBuiltin)
            }
            guard let bounds = rects.map(\.0).reduce(nil, { (acc: CGRect?, r) in acc?.union(r) ?? r })
            else { return }

            let pad: CGFloat = 4
            let scale = min((size.width - pad * 2) / bounds.width,
                            (size.height - pad * 2) / bounds.height)
            let offset = CGPoint(
                x: (size.width - bounds.width * scale) / 2 - bounds.minX * scale,
                y: (size.height - bounds.height * scale) / 2 - bounds.minY * scale
            )

            for (rect, isBuiltin) in rects {
                var screen = rect
                if isBuiltin { screen.size.height -= Self.baseBarHeight }
                let s = CGRect(x: screen.minX * scale + offset.x + 1,
                               y: screen.minY * scale + offset.y + 1,
                               width: screen.width * scale - 2,
                               height: screen.height * scale - 2)
                let path = Path(roundedRect: s, cornerRadius: 2)
                if isBuiltin {
                    context.fill(path, with: .color(.accentColor.opacity(0.85)))
                    // Laptop base bar under the screen.
                    let base = CGRect(x: s.minX - 2, y: s.maxY + 1, width: s.width + 4, height: 2)
                    context.fill(Path(roundedRect: base, cornerRadius: 1),
                                 with: .color(.accentColor.opacity(0.85)))
                } else {
                    context.fill(path, with: .color(.secondary.opacity(0.35)))
                    context.stroke(path, with: .color(.secondary), lineWidth: 1)
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if showMirrorBadge {
                Image(systemName: "rectangle.on.rectangle")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(1)
                    .background(.background.opacity(0.8), in: RoundedRectangle(cornerRadius: 2))
            }
        }
    }
}
