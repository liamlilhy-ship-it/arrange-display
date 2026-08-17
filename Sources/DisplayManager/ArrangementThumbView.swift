import SwiftUI

/// Miniature drawing of an arrangement.
/// - Blue marks the main screen; shape tells the display type apart
///   (built-in laptop = screen with a base bar, external = plain rect).
/// - Every screen is numbered in reading order. A display that mirrors
///   another draws as an unnumbered card stacked behind its source.
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
    /// their source's position.
    init(profile: CustomProfile) {
        let ds = profile.displays
        let extendedIdx = ds.indices.filter { ds[$0].mirrorSourceIndex == nil }
            .sorted { ds[$0].y != ds[$1].y ? ds[$0].y < ds[$1].y : ds[$0].x < ds[$1].x }
        var numberByIndex: [Int: Int] = [:]
        var rectByIndex: [Int: CGRect] = [:]
        var items: [Item] = []
        for (n, i) in extendedIdx.enumerated() {
            let d = ds[i]
            let rect = CGRect(x: CGFloat(d.x), y: CGFloat(d.y),
                              width: CGFloat(d.width), height: CGFloat(d.height))
            numberByIndex[i] = n + 1
            rectByIndex[i] = rect
            items.append(Item(rect: rect, isBuiltin: d.isBuiltin,
                              isMain: d.x == 0 && d.y == 0, number: n + 1, stack: 0))
        }
        var mirrorCount: [Int: Int] = [:]
        for i in ds.indices {
            guard let source = ds[i].mirrorSourceIndex, let rect = rectByIndex[source]
            else { continue }
            let stack = (mirrorCount[source] ?? 0) + 1
            mirrorCount[source] = stack
            items.append(Item(rect: rect, isBuiltin: ds[i].isBuiltin,
                              isMain: false, number: numberByIndex[source] ?? 0, stack: stack))
        }
        self.items = items
    }

    private static let baseBarHeight: CGFloat = 90 // in display-point space
    private static let stackOffset: CGFloat = 3 // canvas px per mirror level

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
                if item.stack == 0 {
                    context.draw(
                        Text("\(item.number)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(item.isMain ? .white : .primary),
                        at: CGPoint(x: s.midX, y: s.midY)
                    )
                }
            }
        }
    }
}
