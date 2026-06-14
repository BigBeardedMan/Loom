# Prompt workspace

The Prompt workspace is Loom's build cockpit. It exposes the panes that map to an active implementation loop: terminal for execution, editor for the file tree, Runs for task/run state, agent for tool-running help, and Commands for reusable shell history.

Sidebar label: **Prompt** · icon: `text.cursor`.

## Available panes

- **Terminal** (⌘⇧1) — SwiftTerm-backed shell. See [Terminal overview](../terminal/overview.md).
- **Editor** (⌘⇧2) — File tree with breadcrumb. CodeEdit integration is on the roadmap.
- **Runs** (⌘⇧3) — SwiftData kanban plus live CLI task mirrors and graph-ledger run history.
- **Agent** (⌘⇧4) — Tool-running agent pane. Default provider is Claude Code via OAuth; switch via the picker.
- **Commands** (⌘⇧5 or the command palette) — Shell command history and rerun surface.

You can add multiple of the same kind (e.g. two terminals side-by-side). Use ⌘⌥arrow to pin one to the left and one to the right.

## Working folder

Every Prompt workspace has a **folder URL**. Set it from the workspace inspector. It feeds:

- The **Terminal** pane's `cwd` on launch (and on `cd` reset via the prompt menu).
- The **Editor** pane's file tree root.
- The **Agent** pane's `cwd` (passed to `claude -p`).

If you switch the folder mid-session, the terminal stays where it is — Loom only seeds `cwd` at launch.

## Task → Agent / Terminal handoff

Kanban cards in the Runs pane carry two optional fields:

- `agentPrompt` — text auto-injected into the Agent pane's input when you "Send to agent" from a card.
- `terminalCommand` — shell command auto-injected into the Terminal pane.

See [Task handoff](../tasks/handoff.md) for the trigger UI.

## Live agent tasks

When the Terminal pane detects a foreground CLI agent (`claude`, `codex`, `gemini`, or `lmstudio`), the Runs pane mirrors that session's live task list and graph ledger evidence. See [Live agent tasks](../tasks/live-agent-tasks.md).
