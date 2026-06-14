# Workspaces

A workspace is one named, persistent room in the left rail. Pick a **kind** when you create it; the kind locks in which panes are available, while the shell keeps the same command bar, adaptive inspector, and bottom status bar around every room.

## Four rooms

| Kind | Sidebar label | Icon | Available panes |
| ---- | ------------- | ---- | --------------- |
| `code` | **Prompt** | `text.cursor` | Terminal, Editor, Runs, Agent, Commands |
| `ideas` | **Ideas** | `lightbulb` | Notes, Agent |
| `review` | **Review** | `magnifyingglass` | Preview, Agent |
| `runs` | **Runs** | `rectangle.stack.fill` | Runs, Chat, Agent, Terminal, Commands |

The kind is set at creation and cannot be changed afterward — make a new workspace if you need a different shape.

The `tasks` pane raw value is kept for old layouts, but the visible pane is **Runs**. It combines the SwiftData kanban, live CLI task mirrors, and graph-ledger supervision surface.

## What's persisted

Each workspace persists:

- Its **layout** (pane positions, pins, full-row toggles).
- For **Prompt** workspaces: the working folder URL (drives terminal `cwd`, editor file tree, agent `cwd`).
- For **Ideas** workspaces: the active note in the right-hand pane.
- For **Review** workspaces: the preview URL.
- For **Runs** workspaces: the supervision layout, addable chat panes, and run graph history.

Shell state such as right-rail visibility and the selected inspector tab is stored separately from pane layout, so older layout JSON can keep loading.

Storage lives in SwiftData under the standard application-support container. See [Storage](../architecture/storage.md).

## Switching

- Click a workspace in the sidebar to switch.
- ⌘⇧O flips back to the previous one — handy when you bounce between Prompt and Review.
- ⌘K opens the command palette for fuzzy search.

## Sessions and runs

A workspace is not the same as a session. Sessions are CLI agent runs (Claude Code, Codex, Gemini, or Loom's bundled `lmstudio`) that Loom polls from local task logs and surfaces in the Runs pane. See [Live agent tasks](../tasks/live-agent-tasks.md).

The Runs room also reads graph ledgers from `~/.loom/agent-runs/<rootRunId>/events.jsonl`, giving the right rail enough evidence for history, review signals, tool previews, handoffs, and ship-readiness summaries.
