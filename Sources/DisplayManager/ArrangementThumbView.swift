import SwiftUI

/// Miniature drawing of an arrangement.
/// - Blue marks the main screen; shape tells the display type apart
///   (built-in laptop = screen with a base bar, external = plain rect).
/// - Every screen is numbered in reading order. A mirror set draws as one
///   rect (the screens show the same content) with a mirror glyph on it.
struct ArrangementThumbView: View {
    struct Item {
        let rect: CGRect // in display-point space
        let isBuiltin: Bool
        let isMain: Bool
        let number: Int
        let hasMirror: Bool // another display mirrors this one
    }

    let items: [Item]

    init(placements: [PresetPlacement]) {
        // Reading order: top row first, then left to right.
        let sorted = placements.sorted {
            $0.origin.y != $1.origin.y ? $0.origin.y < $1.origin.y : $0.origin.x < $1.origin.x
        }
        items = sorted.enumerated().map { i, p in
            Item(rect: CGRect(origin: p.origin, size: p.display.bounds.size),
                 isBuiltin: p.display.isBuiltin,
                 isMain: p.origin == .zero,
                 number: i + 1,
                 hasMirror: false)
        }
    }

    /// Reconstructed from a saved profile's geometry. Mirrored displays are
    /// hidden behind their source, so the source rect carries a mirror glyph.
    init(profile: CustomProfile) {
        let mirroredUUIDs = Set(profile.displays.compactMap(\.mirrorSourceUUID))
        let extended = profile.displays.filter { $0.mirrorSourceUUID == nil }
            .sorted { $0.y != $1.y ? $0.y < $1.y : $0.x < $1.x }
        items = extended.enumerated().map { i, d in
            Item(rect: CGRect(x: CGFloat(d.x), y: CGFloat(d.y),
                              width: CGFloat(d.width), height: CGFloat(d.height)),
                 isBuiltin: d.isBuiltin,
                 isMain: d.x == 0 && d.y == 0,
                 number: i + 1,
                 hasMirror: mirroredUUIDs.contains(d.uuid))
        }
    }

    private static let baseBarHeight: CGFloat = 90 // in display-point space

    var body: some View {
        Canvas { context, size in
            let pointRects = items.map { item -> CGRect in
                var r = item.rect
                if item.isBuiltin { r.size.height += Self.baseBarHeight }
                return r
            }
            guard let bounds = pointRects.reduce(nil, { (acc: CGRect?, r) in acc?.union(r) ?? r })
            else { return }

            let pad: CGFloat = 4
            let scale = min((size.width - pad * 2) / bounds.width,
                            (size.height - pad * 2) / bounds.height)
            let offset = CGPoint(
                x: (size.width - bounds.width * scale) / 2 - bounds.minX * scale,
                y: (size.height - bounds.height * scale) / 2 - bounds.minY * scale
            )

            for item in items {
                let s = CGRect(x: item.rect.minX * scale + offset.x + 1,
                               y: item.rect.minY * scale + offset.y + 1,
                               width: item.rect.width * scale - 2,
                               height: item.rect.height * scale - 2)
                let fill: Color = item.isMain ? .blue : Color.secondary.opacity(0.35)
                let onFill: Color = item.isMain ? .white : .primary
                let path = Path(roundedRect: s, cornerRadius: 2)
                context.fill(path, with: .color(fill))
                if !item.isMain {
                    context.stroke(path, with: .color(.secondary), lineWidth: 1)
                }
                if item.isBuiltin {
                    // Laptop base bar under the screen.
                    let base = CGRect(x: s.minX - 2, y: s.maxY + 1, width: s.width + 4, height: 2)
                    context.fill(Path(roundedRect: base, cornerRadius: 1), with: .color(fill))
                }
                context.draw(
                    Text("\(item.number)")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(onFill),
                    at: CGPoint(x: s.midX, y: s.midY)
                )
                if item.hasMirror {
                    context.draw(
                        Text(Image(systemName: "rectangle.on.rectangle"))
                            .font(.system(size: 6, weight: .bold))
                            .foregroundColor(onFill),
                        at: CGPoint(x: s.maxX - 7, y: s.minY + 6)
                    )
                }
            }
        }
    }
}
