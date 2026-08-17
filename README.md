# Display Manager

Menu bar app for one-click macOS display arrangement profiles.

## Build & run

```bash
./build.sh
open build/DisplayManager.app
```

Look for the two-displays icon in the menu bar. Click a profile to apply it — a toast confirms success. "Display Settings…" jumps to System Settings → Displays.

## Custom profiles

"Save Current as Profile…" snapshots the current arrangement — positions, main display, and mirroring state — pinned to each physical display's hardware UUID. Right-click a saved profile to rename or delete it. A profile is grayed out unless exactly its saved displays are connected; profiles containing mirrored displays show a mirror badge.

## Presets

- **A — External above, built-in below** (needs 1 external)
- **B — Dual external, built-in right** (needs 2 externals; bottom-aligned)
- **C — Dual external, built-in bottom** (needs 2 externals; built-in centered under the seam)

Presets compute geometry from the actual point sizes of connected displays and set the left-most external as the main display. Profiles that don't match the connected display count are grayed out.

## CLI (for testing/scripting)

```bash
.build/release/DisplayManager list             # show connected displays
.build/release/DisplayManager apply <a|b|c>    # apply a preset
.build/release/DisplayManager capture <path>   # save current arrangement to JSON
.build/release/DisplayManager restore <path>   # apply arrangement from JSON
.build/release/DisplayManager profiles         # list saved custom profiles
.build/release/DisplayManager profile <name>   # apply a saved custom profile
```
