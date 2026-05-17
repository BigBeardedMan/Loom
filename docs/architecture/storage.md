# Storage

Loom keeps state in three places, each chosen for what it does well.

## SwiftData

Persistent app data — workspaces, kanban, notes.

| Model | Purpose |
| ----- | ------- |
| `Workspace` | One row per workspace, holds kind + folder URL + layout snapshot. |
| `KanbanBoard` | Per-workspace board container. |
| `KanbanColumn` | Status column (Todo / In Progress / In Review / Complete / Cancelled). |
| `KanbanCard` | Title, instructions, knowledge, agent prompt, terminal command, agent name, project path. |
| `IdeaNote` | Title (derived) + body for the Notes pane. |

All schemas live in `Loom/App/LoomApp.swift` inside the `ModelContainer` definition. Default storage location: macOS application support container (managed by SwiftData). Not in iCloud.

## UserDefaults

Lightweight settings + lists where SwiftData would be overkill.

| Key | Type | Purpose |
| --- | ---- | ------- |
| `loom.appearance` | String (`AppearanceSetting` rawValue) | Theme — match-system / light / dark. |
| `loom.tasks.staleHours` | Double | Live agent tasks stale window (in hours). |
| `loom.localEndpoints` | Data (JSON `[LocalEndpoint]`) | User-configured local LLM endpoints. |
| `loom.agent.maxTurns` | Int | Max tool-call rounds for one local-agent run. |
| `loom.agent.allowBash` | Bool | Enables the local-agent `run_bash` tool. |
| `loom.shellIntegration` | Bool | Enables the zsh command-history shim. |
| `loom.terminal.pasteAsPlainText` | Bool | Sends terminal text paste directly to the PTY. |
| `loom.terminalHistory.enabled` | Bool | Enables local terminal transcript persistence. |
| `loom.terminalHistory.maxBytes` | Double | Terminal transcript storage cap in bytes. Defaults to 1 GB. |

`@AppStorage` reads these in views; the `LocalEndpointStore` reads/writes the JSON blob directly.

## Keychain

Secrets only. Service: `com.chasesims.Loom`.

| Account | Secret |
| ------- | ------ |
| `anthropic_api_key` | Anthropic API key for direct-API agent provider. |
| `local_endpoint_<UUID>` | Bearer token for a local OpenAI-compatible endpoint with auth turned on. |

See [Keychain keys](../reference/keychain-keys.md) for the full list and rotation paths.

## What we don't persist

- **Agent message history** — in-memory only. Closing a workspace and reopening it within the same session preserves messages; quitting the app loses them.
- **Live terminal scrollback** — SwiftTerm holds it in memory. Testing Edition
  saves separate transcript files under Application Support when terminal
  history is enabled.
- **In-flight HTTP requests / subprocesses** — all canceled on quit.

## What about iCloud?

Out of scope. Loom is a single-device personal tool; cross-device sync would mean handling SwiftData CloudKit conflicts, Keychain access groups, and a privacy story. None of that pays back for a one-builder app today.
