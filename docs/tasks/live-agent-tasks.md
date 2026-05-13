# Live agent tasks

When a CLI agent runs in your Terminal pane, Loom mirrors its task list into the Tasks pane in real time.

## Where the data comes from

**Claude Code** writes per-session task state to:

```
~/.claude/tasks/<session-id>/<task-id>.json
```

Each JSON file describes one task: id, title, status (`pending`, `in_progress`, `complete`), parent session, timestamps.

**Codex** records its plan inside the rollout JSONL it writes for each session:

```
~/.codex/sessions/YYYY/MM/DD/rollout-<ts>-<uuid>.jsonl
```

Loom scans the rollout for `update_plan` function calls and surfaces the most recent plan from each rollout that's been touched inside the active window. Status maps directly: `pending`, `in_progress`, `completed`.

**Gemini CLI** does not currently write plan state to disk in any format Loom can read; Gemini terminals show in the agent picker but won't appear in the Tasks pane until the CLI emits a structured plan log.

Loom polls every **2 seconds** via `LiveAgentTasksService` and groups results by source + session id.

## What you see

In a Prompt workspace's Tasks pane, live agent tasks appear in their own section above the kanban columns:

- Header: **Live · &lt;session-id-prefix&gt;** (e.g. `Live · 33280421`).
- One row per task, with a status badge (•, ▶, ✓).
- Click a task to expand and read its full description.

When the session finishes (or the session id rotates), the live block clears.

## Multiple sessions

If you have several CLI agents running across multiple Terminal panes — or if Claude Code is also running outside Loom — the pane shows all live sessions, each with its own header. Use the workspace's **Stale window** (Settings → Tasks) to hide sessions that haven't been touched recently.

## Stale window

Configurable in [Settings → Tasks](../settings/tasks.md). Sessions whose most recent task update is older than the window are treated as dead and hidden:

| Window | Hides sessions older than |
| ------ | ------------------------- |
| 30 minutes | 30 min |
| 1 hour | 1h (default) |
| 4 hours | 4h |
| 12 hours | 12h |
| 24 hours | 24h |
| Never | (always shows everything) |

The poll keeps running regardless of the window — it's purely a display filter.

## Privacy

Loom only reads files under `~/.claude/tasks/` and `~/.codex/sessions/`. Nothing leaves your machine. The polling service uses standard FileManager calls and does not watch via FSEvents (which would require a separate privacy entitlement).

## Clearing sessions

Every session in the Tasks pane has a × button, and the trash icon in the header runs "Clear all". What happens on disk depends on the source:

- **Claude Code** task JSON files are deleted (the session directory stays so the lock file is undisturbed). If the session is still live it rewrites its tasks on the next turn; truly stuck/zombie sessions stay gone.
- **Codex** rollout files are left untouched — they hold the conversation history, so deleting them would destroy more than the plan. Instead Loom records a dismissal timestamp keyed to the session and hides the group until the rollout file's mtime advances past that mark. An active Codex session reappears after its next event; a stuck session stays cleared.
- **Gemini** is currently never collected from disk, so there's nothing to clear; the same dismissal mechanism applies if a future Gemini source is added.

Dismissals persist across launches via `UserDefaults` key `loom.tasks.dismissedSessions`.
