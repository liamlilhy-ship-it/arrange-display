import SwiftUI

/// Miniature drawing of an arrangement.
/// - Blue marks the main screen; shape tells the display type apart
///   (built-in laptop = screen with a base bar, external = plain rect).
/// - Every screen is numbered; displays that mirror another draw as a
///   stacked card behind their source with the same number.
struct ArrangementThumbView: View {
    struct Item {
        let rect: CGRect // in display-point space
        let isBuiltin: Bool
        let isMain: Bool
        let number: Int
        let stack: Int // 0 = extended; 1+ = nth mirror of its source, drawn offset behind
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
                 stack: 0)
        }
    }

    /// Reconstructed from a saved profile's geometry. Mirrored displays share
    /// their source's position and number.
    init(profile: CustomProfile) {
        let extended = profile.displays.filter { $0.mirrorSourceUUID == nil }
            .sorted { $0.y != $1.y ? $0.y < $1.y : $0.x < $1.x }
        var sourceByUUID: [String: (number: Int, rect: CGRect)] = [:]
        var items: [Item] = []
        for (i, d) in extended.enumerated() {
            let rect = CGRect(x: CGFloat(d.x), y: CGFloat(d.y),
                              width: CGFloat(d.width), height: CGFloat(d.height))
            sourceByUUID[d.uuid] = (i + 1, rect)
            items.append(Item(rect: rect, isBuiltin: d.isBuiltin,
                              isMain: d.x == 0 && d.y == 0, number: i + 1, stack: 0))
        }
        var mirrorCount: [String: Int] = [:]
        for d in profile.displays {
            guard let sourceUUID = d.mirrorSourceUUID, let source = sourceByUUID[sourceUUID]
            else { continue }
            let stack = (mirrorCount[sourceUUID] ?? 0) + 1
            mirrorCount[sourceUUID] = stack
            items.append(Item(rect: source.rect, isBuiltin: d.isBuiltin,
                              isMain: false, number: source.number, stack: stack))
        }
        self.items = items
    }

    private static let baseBarHeight: CGFloat = 90 // in display-point space
    private static let stackOffset: CGFloat = 5 // canvas px per mirror level

    var body: some View {
        Canvas { context, size in
            let pointRects = items.map { item -> CGRect in
                var r = item.rect
                if item.isBuiltin { r.size.height += Self.baseBarHeight }
                return r
            }
            guard let bounds = pointRects.reduce(nil, { (acc: CGRect?, r) in acc?.union(r) ?? r })
            else { return }

            let maxStack = items.map(\.stack).max() ?? 0
            let pad: CGFloat = 4 + Self.stackOffset * CGFloat(maxStack)
            let scale = min((size.width - pad * 2) / bounds.width,
                            (size.height - pad * 2) / bounds.height)
            let offset = CGPoint(
                x: (size.width - bounds.width * scale) / 2 - bounds.minX * scale,
                y: (size.height - bounds.height * scale) / 2 - bounds.minY * scale
            )

            // Mirrors first so they sit behind their source.
            for item in items.sorted(by: { $0.stack > $1.stack }) {
                let stackShift = Self.stackOffset * CGFloat(item.stack)
                let s = CGRect(x: item.rect.minX * scale + offset.x + 1 + stackShift,
                               y: item.rect.minY * scale + offset.y + 1 - stackShift,
                               width: item.rect.width * scale - 2,
                               height: item.rect.height * scale - 2)
                let fill: Color = item.isMain ? .blue : Color.secondary.opacity(0.35)
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
                // Mirrors are mostly hidden behind their source, so their
                // (matching) number goes in the visible top-right strip.
                let numberAt = item.stack == 0
                    ? CGPoint(x: s.midX, y: s.midY)
                    : CGPoint(x: s.maxX - 5, y: s.minY + 5)
                context.draw(
                    Text("\(item.number)")
                        .font(.system(size: item.stack == 0 ? 8 : 6, weight: .bold))
                        .foregroundColor(item.isMain ? .white : .primary),
                    at: numberAt
                )
            }
        }
    }
}
