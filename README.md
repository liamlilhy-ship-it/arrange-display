# Arrange Display

One-click macOS display arrangement presets from the menu bar. Save how your monitors are arranged — positions, main display, mirroring, resolution and refresh rate — and restore any setup with a single click, without ever opening System Settings.

<img src="docs/panel.png" width="330" alt="Arrange Display menu bar panel">

## Requirements

- **macOS 26 (Tahoe) or later** — the panel is built on the Liquid Glass design APIs
- **Apple Silicon** Mac (M1 or newer)

## Download

- **[⬇ Download ArrangeDisplay.dmg](https://github.com/liamlilhy-ship-it/arrange-display/releases/latest/download/ArrangeDisplay.dmg)** — open it and drag the app into the Applications shortcut
- [ArrangeDisplay.zip](https://github.com/liamlilhy-ship-it/arrange-display/releases/latest/download/ArrangeDisplay.zip) (plain zip) · [All releases](https://github.com/liamlilhy-ship-it/arrange-display/releases)

The app is self-signed, so the **first launch** must be: right-click the app → **Open** → **Open**. After that it opens normally.

## User manual

Click the two-displays icon in the menu bar to open the panel. Click any preset to apply it — a banner confirms, and the green dot in the Current section shows how many external monitors are detected.

### Key features

- **One-click presets** — each preset restores screen positions, the main display, mirroring, and each monitor's resolution / scaling / refresh rate
- **Hotkeys** — ⌃⌘1 through ⌃⌘9 apply the first nine presets from anywhere, no permission prompts; the numbers follow the menu order, each row shows its key, and a floating confirmation appears when the menu is closed
- **Fits any matching hardware** — a preset applies whenever the connected screen counts match (laptop + N externals); externals are assigned left-to-right and positions scale to the real monitor sizes
- **Exact-monitor memory** — when the very monitors a preset was saved with are connected, each one silently gets its remembered position and display mode back
- **Current section** — a live thumbnail of the present arrangement with the external-monitor count; "Save as Preset…" captures it with an auto-suggested name
- **Organize** — ⋯ on any row (or right-click) for Reorder / Rename / Delete; duplicate names are rejected with a warning
- **Two panel styles** — Blur (translucent Liquid Glass, adjustable frost) or Clear (blur-free dark panel, adjustable transparency), switched in Settings (gear icon)
- **English / 中文** — switch the interface language in Settings
- **Display Settings… shortcut** — jumps straight to System Settings → Displays

In the row thumbnails: blue = main screen, the laptop shape = built-in display, numbers = screen order, stacked cards = mirrored displays.

### Default presets

Three presets ship with the app (they can be renamed, reordered, or deleted like any other):

| Preset | Needs | Arrangement |
|---|---|---|
| 1 external, built-in bottom | 1 external + laptop | External on top (main), laptop centered underneath |
| 2 externals, built-in right | 2 externals + laptop | Two externals side by side (left one main), laptop to the right |
| 2 externals, built-in bottom | 2 externals + laptop | Two externals side by side (left one main), laptop bottom-middle |

Presets that don't fit the currently connected screens appear dimmed until the matching monitors are plugged in.

## Build from source

```bash
./build.sh
open build/DisplayManager.app
```

## CLI (for testing/scripting)

```bash
.build/release/DisplayManager list             # show connected displays
.build/release/DisplayManager apply <a|b|c>    # apply a built-in preset
.build/release/DisplayManager capture <path>   # save current arrangement to JSON
.build/release/DisplayManager restore <path>   # apply arrangement from JSON
.build/release/DisplayManager profiles         # list saved presets
.build/release/DisplayManager profile <name>   # apply a saved preset
```
