# Workspaces

A workspace is one named, persistent layout in the sidebar. Pick a **kind** when you create it; the kind locks in which panes are available.

## Three kinds

| Kind | Sidebar label | Icon | Available panes |
| ---- | ------------- | ---- | --------------- |
| `code` | **Prompt** | `text.cursor` | Terminal, Editor, Tasks, Agent |
| `ideas` | **Ideas** | `lightbulb` | Notes, Agent |
| `review` | **Review** | `magnifyingglass` | Preview, Agent |

The kind is set at creation and cannot be changed afterward — make a new workspace if you need a different shape.

## What's persisted

Each workspace persists:

- Its **layout** (pane positions, pins, full-row toggles).
- For **Prompt** workspaces: the working folder URL (drives terminal `cwd`, editor file tree, agent `cwd`).
- For **Ideas** workspaces: the active note in the right-hand pane.
- For **Review** workspaces: the preview URL.

Storage lives in SwiftData under the standard application-support container. See [Storage](../architecture/storage.md).

## Switching

- Click a workspace in the sidebar to switch.
- ⌘⇧O flips back to the previous one — handy when you bounce between Prompt and Review.
- ⌘K opens the command palette for fuzzy search.

## Sessions

A workspace is not the same as a session. Sessions are CLI agent runs (Claude Code, Codex, Gemini) that Loom polls from `~/.claude/tasks/<session>/<id>.json` and surfaces in the Tasks pane. See [Live agent tasks](../tasks/live-agent-tasks.md).

Some workspace kinds (Review) don't surface sessions because the Tasks pane isn't part of their layout — sidebar shows "Review workspaces don't have sessions yet."
