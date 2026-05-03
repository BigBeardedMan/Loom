# Settings → Appearance

Theme picker. Three values:

- **Match System** — follows macOS's appearance toggle.
- **Light** — pin to light mode.
- **Dark** — pin to dark mode (default).

Stored in `UserDefaults` under key `loom.appearance`. The change applies to every Loom window immediately.

## Why a pin override?

macOS's "match system" works for most apps, but Loom's UI is heavily tuned for dark — the agent pane's accent color, the terminal's background, the kanban card chrome. If you live in light mode generally but want Loom dark always, this is where to set it.

## Tinting

There's no per-pane theme today. The accent color (orange) is fixed in the asset catalog (`AccentColor`). To change it, edit `Loom/Resources/Assets.xcassets/AccentColor.colorset` and rebuild.
