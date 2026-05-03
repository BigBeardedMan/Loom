# Settings → Tasks

Controls the [live agent tasks](../tasks/live-agent-tasks.md) pane.

## Stale window

How long an idle CLI session stays visible in the Tasks pane:

| Option | Hides sessions whose last task update is older than |
| ------ | --------------------------------------------------- |
| 30 minutes | 30 min |
| 1 hour | 1h (default) |
| 4 hours | 4h |
| 12 hours | 12h |
| 24 hours | 24h |
| Never | — (always show all) |

Stored in `UserDefaults` under key `loom.tasks.staleHours` (Double, in hours).

## What it doesn't affect

- The polling cadence — Loom always polls `~/.claude/tasks/` every 2 seconds while a workspace is open.
- Already-finished sessions vs idle sessions — both count as "stale" once their last update is older than the window.
- Persistent kanban cards in the Tasks pane (those don't expire).

## When to lower it

If you cycle through many short Claude Code runs and don't want yesterday's sessions cluttering the pane, drop the window to 30 minutes. The pane stays focused on what's actually live.

## When to raise it

If you have a long-running agent that goes idle for hours between turns, raise the window so it doesn't disappear from the pane mid-session.
