# Terminal

Loom's Terminal pane is a real terminal, backed by [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm). It runs your login shell with a TTY, so interactive tools (Vim, top, fzf, ssh sessions) work the same as they do in iTerm.

## What it ships with

- Login shell (`/bin/zsh -l` by default; respects `$SHELL`).
- TTY allocation (so things like `top` and `bat` get a width).
- Working directory seeded from the workspace folder.
- Standard ANSI color and 256-color support; truecolor via SwiftTerm.
- Claude click-to-edit: clicking inside an active Claude prompt moves the
  cursor to that spot.
- Local transcript persistence with Recently Closed and Recently Deleted
  recovery in Testing Edition.

## What it doesn't have (yet)

- **Inline cards rendered alongside scrollback**: today the per-pane card view *replaces* the live PTY (toggle in pane header). Cards interleaved with raw output is a future expansion.
- **Process resurrection**: recovered sessions open a saved transcript and can
  start a fresh shell in the same folder, but the old process is not resumed.
- **Built-in SSH session manager**: out of scope. Use `ssh` like normal.

## Card view

Every pane's header has a toggle (`list.bullet.rectangle`) that flips between the live PTY and a vertical stack of cards. The cards are rendered from the JSONL log, filtered to that pane's `LOOM_SESSION_ID`, so each pane shows only the commands it ran.

Per-card actions: copy command to pasteboard, rerun in the workspace's first terminal session. The status badge is green for exit 0 and orange `×` for non-zero. Mode is per-pane and not persisted across launches.

## Multi-pane splits

A single Terminal block can host up to four PTY sessions arranged side by side, stacked, or as a 2x2 grid. Each pane runs its own login shell; the cwd of the pane you split *from* seeds the cwd of the new pane.

Pane header buttons (right side):

- **Split** (`+ rectangle on rectangle`) — adds a new pane to this block, capped at four. Visible when fewer than four panes are open.
- **Axis toggle** (`rectangle.split.1x2` / `2x1`) — at 2 or 3 panes, flips between left-right and top-bottom layout. Hidden at 1 pane (no split) and 4 panes (always rendered as a 2x2 quad).
- **Close pane** (`xmark.circle`) — removes that pane and cleans up its PTY. Hidden when the block only has one pane.
- **Send Ctrl-C** (`stop.circle`) — same as before; sends an interrupt to the foreground process of *this* pane only.

Splits use SwiftUI's native `HSplitView` / `VSplitView`, so the divider between panes is draggable.

Layouts persist: the next time you open the workspace, the panes return with the same axis, count, and per-pane cwd. PTYs themselves don't survive relaunch — each restored pane spawns a fresh shell in its saved directory.

## Session transcripts and recovery

Testing Edition saves terminal output locally as raw ANSI transcripts under
`~/Library/Application Support/Loom Testing Edition/Terminal History/`.
Closing a Terminal block moves its saved transcript into **Recently Closed** in
the Prompt workspace sidebar. Click a row to read the transcript, or use
**Start Fresh Shell Here** to open a new terminal at the saved folder.

The bottom of the Terminal Sessions section has **Recently Deleted**. From
there you can recover a transcript back to Recently Closed or delete it
permanently.

Settings -> Shell -> Terminal History controls this feature:

- **Save terminal transcripts locally** turns transcript writes on or off.
- **Storage limit** defaults to 1 GB and can be set from 250 MB to 10 GB.
- **Prune Terminal History** clears saved transcripts. Active terminals keep
  running, but their saved transcript files start over.
- **Reveal History Folder** opens the transcript folder in Finder.

When saved history exceeds the limit, Loom prunes old closed/deleted
transcripts first and does not kill active terminal panes.

## Working directory

The terminal launches in the workspace's folder URL. Subsequent `cd`s persist within the session. Restart the pane (× then re-add) to reset to the workspace folder.

## Copy / paste / image drop

Standard macOS shortcuts: ⌘C copies the selection, ⌘V pastes. Selection works with mouse drag. There's no "select rectangle" mode today.

When the focused Terminal pane receives an image-only pasteboard, Loom inserts an editable Codex image argument instead of sending image bytes to the PTY:

```sh
--image '<path>'
```

Loom also inserts a trailing space after the argument. Copied image files from Finder reuse the original file path. Direct clipboard images, such as screenshots, are encoded as PNG files under `~/Library/Application Support/Loom Testing Edition/Clipboard Images/` in the Testing Edition build. Loom never presses Return for this path; the command stays editable so you can review it before running it.

If the clipboard contains both text and image data, text paste wins. That keeps rich copies from browsers and documents from unexpectedly turning into image arguments. ⇧⌘V keeps its existing plain-text behavior for text paste, and uses the same image argument behavior only when no text is available.

Dragging an image file or raw image data onto a Terminal pane uses the same command shape. Loom inserts `--image '<path>' ` at the cursor, keeps Finder-dragged image file paths intact, saves raw image drags as PNG files in the same Clipboard Images folder, and never presses Return.

## Scrollback

SwiftTerm keeps the default 1000-line live scrollback. Scroll with two-finger
drag or the keyboard's Page Up / Page Down (depending on terminal app's
`terminfo`). Live scrollback is separate from the saved transcript files.

## The terminal as the differentiator

Loom's product principle: **terminal work should be reviewable**. Today that means giving the terminal first-class real-estate alongside the editor and agent. As Loom evolves the terminal will accumulate structure — command boundaries, exit codes, agent-issued vs human-issued commands — that other tools throw away as scrollback.
