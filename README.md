# Arrange Display

Menu bar app for one-click macOS display arrangement presets.

## Build & run

```bash
./build.sh
open build/DisplayManager.app
```

Look for the two-displays icon in the menu bar. Click a preset to apply it — a toast confirms success. "Display Settings…" jumps to System Settings → Displays.

## Presets

A preset is a saved screen arrangement — positions, main display, mirroring, and each monitor's display mode (resolution, scaling, refresh rate). It fits whenever the connected screen counts match (laptop + N externals): externals are assigned left-to-right and positions scale to the real monitor sizes. When the exact monitors it was saved with are connected, each physical monitor silently gets its remembered position and display mode instead; a mode that's no longer offered is skipped without blocking the arrangement.

Click a row to apply (a toast confirms); ⋯ or right-click for Reorder / Rename / Delete. The gear icon opens Settings: a Frost slider for the panel's glass transparency and an English/中文 language switch.

In thumbnails, blue marks the main screen, the built-in display is drawn as a laptop (screen with base bar), and screens are numbered — mirrored displays draw as stacked cards behind their source.

## CLI (for testing/scripting)

```bash
.build/release/DisplayManager list             # show connected displays
.build/release/DisplayManager apply <a|b|c>    # apply a built-in preset
.build/release/DisplayManager capture <path>   # save current arrangement to JSON
.build/release/DisplayManager restore <path>   # apply arrangement from JSON
.build/release/DisplayManager profiles         # list saved presets
.build/release/DisplayManager profile <name>   # apply a saved preset
```
