# CLI agent detection

When a CLI agent runs in the foreground of a Terminal pane, Loom recognizes it and lights up integrations.

## What gets detected

Today three commands are detected by name:

- `claude` — Claude Code
- `codex` — OpenAI Codex CLI
- `gemini` — Google Gemini CLI

Detection is by foreground process name. If you alias these (e.g. `alias c=claude`), the alias is what runs — Loom sees the underlying executable name via the TTY's foreground process group.

## What lights up

When detection fires:

- The **Tasks pane** in the same workspace mirrors the agent's live task state from `~/.claude/tasks/<session-id>/`. See [Live agent tasks](../tasks/live-agent-tasks.md).
- The Terminal pane's title bar adds an `Agent: <name>` indicator.
- The Tasks pane's header shows the session id prefix so you can correlate panes if you have multiple agents running.

When the agent process exits, detection drops and the live-task block fades to history.

## Why name-based?

A more reliable detection path is "look at the JSON files this CLI writes." That's exactly what the Tasks pane does — but for the Terminal pane's own indicators we just need a quick visual cue, and the foreground process name is fast and dependency-free.

If you need to add another CLI to the recognized set, edit `Loom/Terminal/TerminalSession.swift`'s detection enum and rebuild.
