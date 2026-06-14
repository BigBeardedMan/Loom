# First run

When Loom opens for the first time it seeds four rooms in the left rail: **Prompt**, **Ideas**, **Review**, and **Runs**. You can start in one of those or create another workspace:

1. Click **+** in the top-left of the sidebar (or press ⌘N).
2. Pick a **kind** - Prompt, Ideas, Review, or Runs. The kind determines which panes can be added later.
3. Name the workspace and confirm.
4. Add panes via the top-right add strip, the **Add Block** menu, or ⌘⇧1 through ⌘⇧5. Keys map to the available panels for the current room.

## Pick the right workspace kind

| Kind | Available panes | Use it for |
| ---- | --------------- | ---------- |
| **Prompt** | Terminal, Editor, Runs, Agent, Commands | Active build / debug sessions. The cockpit. |
| **Ideas** | Notes, Agent | Drafting, idea capture, low-stakes brainstorming with a model. |
| **Review** | Preview, Agent | Looking at a localhost preview or rendered output side-by-side with an agent. |
| **Runs** | Runs, Chat, Agent, Terminal, Commands | Supervising agent graphs, history, chats, handoffs, and review evidence. |

Switch between kinds freely — each kind remembers its own layout and pane order.

## Try the agent pane

By default the Agent pane talks to Claude Code via your existing CLI OAuth login. You don't need to enter an API key.

1. Add an Agent pane (⌘⇧4 in a Prompt workspace).
2. The header shows `Claude Code · <session-id>`.
3. Type a prompt at the bottom and press Return.
4. Loom spawns `claude -p --session-id <uuid> '<your prompt>'` under the hood and waits for the response.

To swap providers (built-in agents, local LLMs), see [Agents → Overview](../agents/overview.md).

## Pin a pane to the side

The default layout is a tile grid. Use **Layout -> Pin Left/Right/Top/Bottom** (⌘⌥ + arrow) to dock the focused pane to an edge - useful for keeping the terminal full-height while the editor and Runs pane float to the right.

## Open the command palette

Press ⌘K to fuzzy-search workspaces, panes, and recent actions. Press ⌘⇧O to flip back to your previous workspace.
