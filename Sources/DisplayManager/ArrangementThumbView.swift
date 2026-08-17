import SwiftUI

/// Miniature drawing of an arrangement: externals as plain rounded rects,
/// the built-in display as a rect with a laptop base bar underneath.
struct ArrangementThumbView: View {
    let placements: [PresetPlacement]

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
    }
}
