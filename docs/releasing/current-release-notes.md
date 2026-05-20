## Changes

- LM Studio is now a first-class Agent pane provider in Testing Edition. If its local server is already running, Settings -> Providers offers a one-click **Add LM Studio** shortcut.
- LM Studio model discovery now uses `/api/v0/models` first, so loaded models appear first with context length, quantization, and architecture details in the model picker and Agent picker.
- The Agent pane defaults LM Studio to Agent Mode, shows a compact local-model status strip, and adds permission modes: Ask, Plan, Accept Edits, and Bypass Permissions.
- In-app LM Studio tool execution now honors those permission modes: Plan blocks edits/bash, Accept Edits auto-approves file edits, and Bypass Permissions auto-approves edits and shell commands for the run.
- The bundled `lmstudio` helper no longer crashes when printing `--help`.
- Terminal sessions now save local transcripts in Testing Edition. Closed panes appear under **Recently Closed**, with a transcript reader and **Start Fresh Shell Here** action.
- Terminal Sessions now includes **Recently Deleted** so deleted transcripts can be recovered or deleted permanently.
- Settings -> Shell now has Terminal History controls: save on/off, a user-selectable storage cap that defaults to 1 GB, current usage, prune, and reveal-folder actions.
- Claude shell text editing is now click-aware: clicking inside an active Claude prompt moves the cursor to that spot without broadening the behavior to Codex, Gemini, or plain shells.
- Usage limit warnings now poll readable local limit snapshots every 20 minutes and on app open/foreground. For this Testing Edition build, the warning threshold is intentionally set to 20% so the badge flow can be tested.
- A red `1` badge appears on usage pills when a tool with readable limit data crosses the test threshold. Opening the dashboard carries the badge to the Limits button, and clicking Limits clears that warning until a newer snapshot crosses the threshold again.
- Terminal panes now accept dragged image files or raw image data and insert editable Codex `--image '<path>' ` arguments without pressing Return.
- Clipboard image paste behavior remains unchanged: text paste still wins for rich copied content, while image-only clipboards insert editable image arguments.
