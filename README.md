# Display Manager

Menu bar app for one-click macOS display arrangement profiles.

## Build & run

```bash
./build.sh
open build/DisplayManager.app
```

Look for the two-displays icon in the menu bar. Click a profile to apply it — a toast confirms success. "Display Settings…" jumps to System Settings → Displays.

## Layouts vs Setups

- **Layouts** are shapes that work with any monitors ("2 externals side by side, laptop below"). They apply to whatever is connected when the external count matches, assigning externals left-to-right. Drawn with dashed thumbnails. Three ship built-in.
- **Setups** are snapshots of your exact monitors — positions, main display, and mirroring — pinned by hardware UUID. "Save Current as Setup…" creates one; it grays out unless exactly those monitors are connected. Drawn solid.

Every row behaves the same: click to apply (a toast confirms), ⋯ or right-click for Edit Arrangement / Rename / Delete. The drag-to-arrange editor supports magnetic edge snapping and Set as Main.

In thumbnails, blue marks the main screen, the built-in display is drawn as a laptop (screen with base bar), and screens are numbered — mirrored displays draw as stacked cards behind their source.

## CLI (for testing/scripting)

```bash
.build/release/DisplayManager list             # show connected displays
.build/release/DisplayManager apply <a|b|c>    # apply a preset
.build/release/DisplayManager capture <path>   # save current arrangement to JSON
.build/release/DisplayManager restore <path>   # apply arrangement from JSON
.build/release/DisplayManager profiles         # list saved custom profiles
.build/release/DisplayManager profile <name>   # apply a saved custom profile
```
