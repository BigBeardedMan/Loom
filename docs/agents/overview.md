# Agents

The Agent pane is a streaming chat surface. Behind the picker, Loom routes prompts to one of two provider families:

| Family | Providers today | How auth works |
| ------ | --------------- | -------------- |
| **CLI subprocess** | [Claude Code](claude-code.md), Codex, Gemini, [lmstudio](lmstudio-cli.md) | Piggybacks on the CLI's existing login or local server. No API key in Loom. |
| **HTTP streaming** | [Ollama](local-llms.md), [OpenAI-compatible](local-llms.md), [Anthropic API](anthropic-api.md) | Configurable base URL, optional bearer token in Keychain. |

The [`lmstudio` CLI](lmstudio-cli.md) is Loom's own terminal agent for local models. Install it with `bin/install-lmstudio.sh`, then run `lmstudio` in any terminal pane. Its tasks land in the Loom Tasks pane automatically via `~/.loom/tasks/`.

## Picker

The picker in the Agent pane's header groups agents by source:

- `Default` — Claude Code's vendor default.
- `Plugin agents` / `Built-in agents` — sub-agents discovered via `claude agents list`.
- `Local · <endpoint name>` — one entry per Ollama model, or one per OpenAI-compatible endpoint, fed by [Settings → Providers](../settings/providers.md).

Click the refresh icon next to the picker to re-query — useful after `claude agents` adds a new sub-agent or after `ollama pull` lands a new model.

## Streaming behavior

| Provider | Streaming | Cancel |
| -------- | --------- | ------ |
| Claude Code | One-shot (full response when subprocess exits) | Stop button terminates the process |
| Ollama | Live token stream | Stop button cancels the URLSession task |
| OpenAI-compatible | Live token stream (SSE) | Stop button cancels the URLSession task |
| Anthropic API | Live token stream (SSE) | Stop button cancels the URLSession task |

The "..." placeholder in an empty assistant bubble means the request is in flight.

## Conversation history

- **CLI providers** retain context server-side via `--resume <session-id>`. The session id is shown in the header (`Claude Code · 3328C421`).
- **HTTP providers** are stateless. Loom replays the full chat history with each turn, so context survives but you'll see longer requests as the conversation grows.

Switching between providers inside one workspace creates a new logical conversation — the new provider doesn't get the prior history of the previous one. Open a fresh workspace to start clean.

## Per-workspace state

Each workspace renders its own Agent pane with local message state. Closing and reopening a workspace preserves the message log (in-memory; not persisted across app relaunches today).

## Workspace-aware proposals

The Agent pane reads the active workspace + active tab via `WorkspaceContext`. In Ideas workspaces this surfaces an inline proposal card under list-shaped responses, letting one click commit the items as new note tabs or append them to the open one. See [Ideas workspace → Save-to-tab proposal cards](../workspaces/ideas.md#save-to-tab-proposal-cards) for the user-facing behavior.

Streaming itself is also fast-pathed: token deltas update an isolated `StreamingBubble` view (not the whole message list), so the chat stays smooth even on Ollama's faster local models.

## Workspace context block

Every prompt the Agent pane sends carries a workspace snapshot so the model can ground its answer in the project you're actually sitting in. The snapshot is rebuilt at send-time and includes:

- **Workspace name + kind** (`Loom (Ideas)`, `vendetta (Prompt)`, …).
- **Project folder path** when the workspace has one configured.
- **Project memory** — Loom reads `CLAUDE.md`, `AGENTS.md`, `GUIDE.md`, and `README.md` from the workspace folder (priority order; capped at ~5 KB total) and pastes them in.
- **Active idea tab** name + body (Ideas workspaces only).
- **Sibling idea tabs** — titles plus a short excerpt of each, so the agent doesn't propose ideas that are already captured.

Wiring is per-provider:

- **Anthropic / Ollama / OpenAI-compatible** receive the snapshot via the `system` prompt every turn.
- **Claude Code / Codex / Gemini** subprocess agents don't take a separate system message, so Loom prepends the snapshot under a `## Loom workspace context` heading and ends the prompt with a `## User request` section before the user's question.

Result: in an Ideas workspace pointed at the Loom folder, asking "give me 8 ideas" returns ideas grounded in Loom's `README.md` + `GUIDE.md` instead of generic suggestions, and the proposal card lands them straight in the active tab.
