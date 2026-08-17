# Display Manager

Menu bar app for one-click macOS display arrangement profiles.

## Build & run

```bash
./build.sh
open build/DisplayManager.app
```

Look for the two-displays icon in the menu bar. Click a profile to apply it — a toast confirms success. "Display Settings…" jumps to System Settings → Displays.

## Profiles

A profile is a saved screen arrangement — positions, main display, and mirroring. It fits whenever the connected screen counts match (laptop + N externals): externals are assigned left-to-right and positions scale to the real monitor sizes. When the exact monitors it was saved with are connected, each physical monitor silently gets its remembered position instead.

Click a row to apply (a toast confirms); ⋯ or right-click for Rename / Delete. "Edit Profiles…" opens the manager window: pick a profile in the sidebar and edit it — drag with magnetic snapping, Set as Main, Mirror menu, Add/Remove screens, Apply Now to preview, Reset, arrow-key nudging.

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
