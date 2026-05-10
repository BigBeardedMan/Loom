# Keyboard shortcuts

Loom is keyboard-first. Every shortcut below is wired in `Loom/App/LoomApp.swift` via the standard macOS `Commands` API, so they show up in the menu bar too.

## Workspaces

| Shortcut | Action |
| -------- | ------ |
| ⌘N | New workspace (focuses the sidebar's name field) |
| ⌘K | Open command palette |
| ⌘⇧O | Switch to previous workspace |

Inside the ⌘K palette, **↑** walks back through the last 50 distinct commands (newest first) and **↓** walks forward, just like a shell prompt. Press ↩ on a populated entry to rerun it in the active terminal.

## Adding panes

The number maps to the panel order for the current workspace kind. In a **Prompt** workspace the order is Terminal, Editor, Tasks, Agent — so ⌘⇧1 adds a terminal, ⌘⇧4 adds an agent. In an **Ideas** workspace ⌘⇧1 adds Notes, ⌘⇧2 adds Agent.

| Shortcut | Action |
| -------- | ------ |
| ⌘⇧1 | Add the first pane available for this kind |
| ⌘⇧2 | Add the second |
| ⌘⇧3 | Add the third |
| ⌘⇧4 | Add the fourth |

## Layout

These act on the **focused** pane. Click into a pane to focus it.

| Shortcut | Action |
| -------- | ------ |
| ⌘⌥← | Pin focused pane to the left edge |
| ⌘⌥→ | Pin focused pane to the right edge |
| ⌘⌥↑ | Pin focused pane to the top |
| ⌘⌥↓ | Pin focused pane to the bottom |
| ⌘⌥F | Toggle full row span |
| ⌘⌥U | Unpin |

## Build & run (Xcode)

When you're hacking on Loom itself in Xcode:

| Shortcut | Action |
| -------- | ------ |
| ⌘R | Build & run |
| ⌘⇧K | Clean build folder |
| ⌘B | Build only |

## Help

| Shortcut | Action |
| -------- | ------ |
| ⌘? | Open the GUIDE on GitHub |
| Help → Loom Help | Open the GUIDE on GitHub |
| Help → Loom Documentation Site | Open the hosted MkDocs site |
| Help → Check for Updates… | Force a remote release check now |

Clicking the **Loom banner** in the top-left of the window also opens the GitHub repo in your browser.
