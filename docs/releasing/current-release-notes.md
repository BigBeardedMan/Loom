## Changes

- Terminal sessions now save local transcripts in Testing Edition. Closed panes appear under **Recently Closed**, with a transcript reader and **Start Fresh Shell Here** action.
- Terminal Sessions now includes **Recently Deleted** so deleted transcripts can be recovered or deleted permanently.
- Settings -> Shell now has Terminal History controls: save on/off, a user-selectable storage cap that defaults to 1 GB, current usage, prune, and reveal-folder actions.
- Claude shell text editing is now click-aware: clicking inside an active Claude prompt moves the cursor to that spot without broadening the behavior to Codex, Gemini, or plain shells.
- Usage limit warnings now poll readable local limit snapshots every 20 minutes and on app open/foreground. For this Testing Edition build, the warning threshold is intentionally set to 20% so the badge flow can be tested.
- A red `1` badge appears on usage pills when a tool with readable limit data crosses the test threshold. Opening the dashboard carries the badge to the Limits button, and clicking Limits clears that warning until a newer snapshot crosses the threshold again.
- Terminal panes now accept dragged image files or raw image data and insert editable Codex `--image '<path>' ` arguments without pressing Return.
- Clipboard image paste behavior remains unchanged: text paste still wins for rich copied content, while image-only clipboards insert editable image arguments.
