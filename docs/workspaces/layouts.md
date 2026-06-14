# Layouts

Every pane in a workspace can be **pinned** to an edge, **spanned** across a full row, resized, and reordered. The deck layout is per-room and persists across launches; shell state such as the right rail's selected tab is stored separately.

## Default layouts

Canonical rooms seed with these layouts:

| Room | Default panes |
| ---- | ------------- |
| Prompt | Terminal, Runs, Agent |
| Ideas | Notes, Agent |
| Review | Preview, Agent |
| Runs | Runs, Chat |

When you add a pane, it joins the current row. Two panes in a row split horizontally; three panes split into thirds; etc. Adding a fourth wraps to a new row.

## Pinning

Pinning docks the focused pane to one edge of the workspace area. The other panes redistribute to the remaining region.

| Shortcut | Action |
| -------- | ------ |
| ⌘⌥← | Pin focused pane to the **left** |
| ⌘⌥→ | Pin focused pane to the **right** |
| ⌘⌥↑ | Pin focused pane to the **top** |
| ⌘⌥↓ | Pin focused pane to the **bottom** |
| ⌘⌥U | **Unpin** |

Only one pane per edge can be pinned at a time. Pinning a second pane to the same edge replaces the first.

## Full-row span

⌘⌥F toggles the focused pane between "shares its row" and "spans the full width of the row." Useful for the Terminal pane when you need a wide command output without unpinning the rest.

## Resizing

Drag the dividers between panes to resize. Sizes persist per workspace.

## Reordering

Drag the pane title bar to reorder. The kanban-style pane menu (top-right of each pane) also has **Move up** / **Move down** items.

## Closing

Click the **x** in a pane's title bar to remove it from the workspace. Re-add from the top-right add strip or the command palette.

## Persistence

Layout is serialized via `LayoutPersistence` and stored in SwiftData alongside the workspace. Switching kinds preserves each kind's last-seen layout — open a Prompt workspace, drop two terminals in, switch to Ideas, switch back: the two terminals are still there.
