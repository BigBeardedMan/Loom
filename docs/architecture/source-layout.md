# Source layout

Loom is one Swift app target with everything under `Loom/`. Nine top-level directories, ~35 Swift files.

```
Loom/
├── App/               @main, scene, environment wiring, update + GitHub release fetcher
├── Workspace/         Four-pane container, layout persistence, sidebar, model
├── Terminal/          SwiftTerm-backed pane + CLI agent detection
├── Editor/            File tree, breadcrumb, FSNode
├── Agents/            Provider abstraction, Anthropic, Claude Code subprocess, Ollama, OpenAI-compatible, registry, agent pane UI, Keychain store
├── Kanban/            SwiftData task board, columns, cards, inspector
├── Notes/             IdeaNote model + notes pane
├── Settings/          Preferences window (Appearance / Tasks / Providers / Advanced)
└── Resources/         Asset catalog, entitlements
```

## App

Bootstraps the app:

- `LoomApp.swift` — `@main`, `WindowGroup` for the workspace view, `Settings` scene, the `Commands` block defining keyboard shortcuts.
- `UpdateService.swift` — orchestrates the auto-update poll/stage/swap flow.
- `GitHubReleaseFetcher.swift` — thin GitHub API client (release lookup, DMG download).
- `Theme.swift` / `LoomLogo.swift` — shared colors, branding, the menu-bar logo.

## Workspace

The four-pane layout system:

- `WorkspaceView.swift` — top-level scene, hosts the sidebar + the active workspace's panes.
- `WorkspaceModel.swift` — SwiftData `Workspace` model + `WorkspaceKind` enum + per-kind `availablePanels`.
- `WorkspaceLayout.swift` — `@Observable` runtime layout state, focus tracking, command-palette routing.
- `LayoutPersistence.swift` — serializes pane positions/pins per workspace kind to SwiftData.
- `WorkspaceSidebarView.swift` — the left rail with workspace list, sessions section, kind picker.
- `StatusLineView.swift` — bottom bar (added in this branch).

## Terminal

- `TerminalPaneView.swift` — SwiftUI host for the SwiftTerm view.
- `TerminalSession.swift` — owns the PTY + foreground-process detection (`claude`, `codex`, `gemini`).

## Editor

- `EditorPaneView.swift` — pane chrome + breadcrumb.
- `FileTreeView.swift` — recursive disclosure outline.
- `FSNode.swift` — value-type node model for the tree.

## Agents

The largest module. See [Agents → Overview](../agents/overview.md):

- `LLMProvider.swift` — protocol, `LLMMessage`, `LLMEvent`, `LLMError`.
- `AnthropicProvider.swift` — direct API streaming.
- `ClaudeCodeProvider.swift` — `claude -p` subprocess with `--session-id` / `--resume`.
- `OllamaProvider.swift` — native Ollama HTTP, `/api/chat` NDJSON stream + `/api/tags` discovery.
- `OpenAICompatibleProvider.swift` — generic `/v1/chat/completions` SSE stream, optional bearer.
- `LocalEndpoint.swift` / `LocalEndpointStore.swift` — user-configured endpoints + UserDefaults+Keychain persistence.
- `AgentRegistry.swift` — vendor enum, descriptor type, `claude agents list` parser, local-endpoint descriptor builder.
- `AgentPaneView.swift` — chat surface, picker, send dispatch, streaming wiring.
- `KeychainStore.swift` — generic `SecItem`-backed store.

## Kanban

- `KanbanBoard.swift` — board / column / card SwiftData models with `agentPrompt`, `terminalCommand`, `agentName`, `projectPath` fields.
- `KanbanPaneView.swift` — column chrome, card grid, inspector.

## Notes

- `IdeaNote.swift` — SwiftData model.
- `NotesPaneView.swift` — note list + editor body.

## Settings

- `SettingsScene.swift` — TabView with Appearance, Tasks, Providers, Advanced.

## Resources

- `Assets.xcassets` — app icon, accent color.
- `Loom.entitlements` — sandbox off, network client on.

## Why no separate logic / view split?

Loom is small enough that the cost of separate `Models/` and `Views/` folders outweighs the benefit. The current layout colocates each module's model, view, and service code so feature work happens in one folder.
