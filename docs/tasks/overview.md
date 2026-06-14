# Runs Pane

The Runs pane is the visible home for task state, live CLI session mirrors, and graph-ledger run history. Its raw layout value is still `tasks` for compatibility with older saved workspaces.

It is available in **Prompt** and **Runs** rooms. Prompt uses it as part of the build cockpit; Runs uses it as the supervision surface next to addable chat panes.

## Columns

The board ships with five fixed columns:

1. **Todo**
2. **In Progress**
3. **In Review**
4. **Complete**
5. **Cancelled**

Drag cards between columns to update status. Column order is fixed.

## Cards

Each card carries:

| Field | Purpose |
| ----- | ------- |
| **Title** | Short label shown on the card. |
| **Instructions** | Long-form description, surfaced in the inspector. |
| **Task knowledge** | Free-form notes, links, prior context. |
| **Agent name** | Optional CLI agent name to use when handing off. |
| **Agent prompt** | Auto-injected into the Agent pane on **Send to agent**. |
| **Terminal command** | Auto-injected into the Terminal pane on **Send to terminal**. |
| **Project path** | Working folder for handoff. Defaults to the workspace folder. |

## Inspector

Click a card to open the inspector. Edit any field; changes save immediately. Press Esc to dismiss.

## Persistence

Cards live in SwiftData under `KanbanCard`. The default container is on disk (not in-memory), so cards survive app relaunches. See [Storage](../architecture/storage.md).

## Live agent tasks

When a CLI agent (`claude`, `codex`, `gemini`, or `lmstudio`) is running in a Terminal pane, the Runs pane mirrors its in-progress task list and refreshes graph-ledger summaries — see [Live agent tasks](live-agent-tasks.md).
