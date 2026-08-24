#!/bin/bash
# Regenerates Resources/AppIcon.icns from the same SF Symbol the menu bar uses.
# Run after changing the artwork; the .icns itself is committed.
set -euo pipefail
cd "$(dirname "$0")"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

cat > "$work/icon.swift" <<'SWIFT'
import AppKit

// The glyph is display.2 — the same symbol as the menu bar item, so the
// dock/Finder icon and the status item read as the same app.
let out = CommandLine.arguments[1]
let size: CGFloat = 1024

let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
    guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

    // macOS icons sit on a squircle inset from the canvas edge.
    let inset = size * 0.0977
    let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let squircle = NSBezierPath(roundedRect: rect,
                                xRadius: rect.width * 0.2237,
                                yRadius: rect.width * 0.2237)

    ctx.saveGState()
    squircle.addClip()
    let bg = NSGradient(colors: [NSColor(srgbRed: 0.30, green: 0.44, blue: 0.78, alpha: 1),
                                NSColor(srgbRed: 0.15, green: 0.22, blue: 0.45, alpha: 1)])!
    bg.draw(in: rect, angle: -90)
    // Faint sheen across the top, echoing the panel's glass.
    NSGradient(colors: [NSColor(white: 1, alpha: 0.18), NSColor(white: 1, alpha: 0)])!
        .draw(in: CGRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2),
              angle: -90)
    ctx.restoreGState()

    let config = NSImage.SymbolConfiguration(pointSize: size * 0.37, weight: .regular)
    if let glyph = NSImage(systemSymbolName: "display.2", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let tinted = NSImage(size: glyph.size, flipped: false) { r in
            glyph.draw(in: r)
            NSColor.white.set()
            r.fill(using: .sourceAtop)
            return true
        }
        let g = tinted.size
        // Nudge up slightly: the symbol's stands sit low, so geometric
        // centring reads as bottom-heavy.
        tinted.draw(in: CGRect(x: (size - g.width) / 2, y: (size - g.height) / 2 + size * 0.02,
                               width: g.width, height: g.height))
    }
    return true
}

let rep = NSBitmapImageRep(cgImage: image.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
rep.size = NSSize(width: size, height: size)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
SWIFT

swift "$work/icon.swift" "$work/icon-1024.png"

set=$work/AppIcon.iconset
mkdir -p "$set"
for s in 16 32 128 256 512; do
    sips -z $s $s "$work/icon-1024.png" --out "$set/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) "$work/icon-1024.png" --out "$set/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$set" -o Resources/AppIcon.icns
echo "Wrote Resources/AppIcon.icns ($(du -h Resources/AppIcon.icns | cut -f1))"
cp "$work/icon-1024.png" "${PREVIEW_OUT:-/dev/null}" 2>/dev/null || true
