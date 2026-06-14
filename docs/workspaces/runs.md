# Runs Workspace

The Runs workspace is Loom's supervision room for agent work. It combines the visible Runs pane, addable chat panes, terminal access, commands, and the adaptive right rail for timeline, memory, tools, diff, and details.

Sidebar label: **Runs** · icon: `rectangle.stack.fill`.

## Available panes

- **Runs** (⌘⇧1) — Kanban cards, live CLI task mirrors, and graph-ledger history.
- **Chat** (⌘⇧2) — Chat-only agent surface. It reuses the Agent chat machinery but starts outside tool-running agent mode.
- **Agent** (⌘⇧3) — Tool-running agent pane for direct execution.
- **Terminal** (⌘⇧4) — SwiftTerm-backed shell for local commands and CLI agents.
- **Commands** (⌘⇧5) — Command history and rerun surface.

The default layout is one Runs pane plus one Chat pane. Additional Chat panes get stable titles: `Chat`, `Chat 2`, `Chat 3`, and so on.

## Run Ledger

Loom records agent graph events under:

```text
~/.loom/agent-runs/<rootRunId>/events.jsonl
```

The Runs room reads those ledgers to show lineage, history, timeline events, summaries, tool previews, handoffs, worktrees, changed files, and reviewability signals. It is visibility-first: it does not add a scheduler, auto-merge behavior, or a new spawn button.

## Right Rail

The adaptive right rail is most useful in Runs:

| Tab | Purpose |
| --- | ------- |
| Timeline | Live task groups and recent run history. |
| Tools | Open pane counts, selected provider, local endpoints, and available agents. |
| Diff | Review packet, changed files, check signals, preview status, and ship decision. |
| Memory | Read-only project memory plus run ledger summaries. |
| Details | Selected pane and room metadata. |

Files and Preview appear when the workspace folder or pane layout makes them relevant.

## Chat vs Agent

Use **Chat** when you want a conversation attached to the room without implying tool-running mode. Use **Agent** when the model should run tools, inspect files, or drive implementation work. Both use the same provider registry and workspace context, but Chat panes are intentionally scoped as non-agent-mode conversations.
