# File paths

Where Loom (and the things Loom reads from) keeps state on disk.

## Loom-owned

| Path | Purpose |
| ---- | ------- |
| `~/Library/Application Support/Loom/staging/Loom.app` | Newly downloaded Loom build, waiting for the Update pill click. |
| `~/Library/Application Support/Loom/staging/manifest.json` | `{ version, build, stagedAt }` for the staged build. |
| `~/Library/Application Support/Loom/layout.json` | Workspace pane layout, custom titles, terminal cwd, and split state. |
| `~/Library/Application Support/Loom/shell/.zshrc` | zsh command-history shim sourced via `ZDOTDIR`. |
| `~/Library/Application Support/Loom/shell/history.jsonl` | Append-only structured command log. |
| `~/Library/Application Support/Loom/shell/output/cap-*.out` | Captured stdout/stderr for Loom-submitted commands. |
| `~/Library/Application Support/Loom/Terminal History/sessions.json` | Terminal transcript metadata and active/closed/deleted state. |
| `~/Library/Application Support/Loom/Terminal History/transcripts/<uuid>.ansi` | Raw ANSI PTY transcript for one terminal session. |
| `~/Library/Application Support/Loom/Clipboard Images/clipboard-*.png` | Raw clipboard or drag image data saved before inserting a Codex `--image` argument. |
| `~/Library/Application Support/com.chasesims.Loom/default.store` | SwiftData store (workspaces, kanban, notes). Path varies by SwiftData version. |
| `~/Library/Preferences/com.chasesims.Loom.plist` | UserDefaults (theme, stale window, local endpoints, shell settings). |

## Loom-read (external)

| Path | Why Loom reads it |
| ---- | ----------------- |
| `~/.claude/tasks/<session-id>/<task-id>.json` | Live agent tasks polling. See [Live agent tasks](../tasks/live-agent-tasks.md). |
| `~/.claude/credentials.json` | Indirectly — `claude` CLI uses it; Loom shells out to `claude`. |
| The workspace's folder URL | Editor file tree root, terminal `cwd`, agent `cwd`. |

## Build / dev paths

| Path | Purpose |
| ---- | ------- |
| `<repo>/` | Wherever you cloned Loom. Build outputs are deliberately *not* under iCloud-synced locations like `~/Documents` — see below. |
| `~/Library/Developer/Xcode/DerivedData/Loom-*/Build/Products/Release/Loom.app` | Loom build output. |
| `<repo>/build/release/Loom-<version>.dmg` | Packaged Loom DMG ready for release upload. |

## Why Application Support, not the app bundle?

The app bundle is read-only after Gatekeeper-blessing it; SwiftData and the staging directory both need write access. Application Support is the standard macOS location for that. It's also what `~/Library` backups (Time Machine, Carbon Copy) snapshot.

## Why not iCloud Drive?

Two reasons:

1. iCloud renames build artifacts mid-build (`Foo` → `Foo 2`) when sync detects a duplicate, which breaks Xcode and DMG packaging.
2. Loom is single-device by design. There's nothing to sync.

If your clone lives under `~/Documents` (which is iCloud-synced for many users), `project.yml`'s pre-build script defensively sweeps `* 2.*` / `* 3.*` shadow files before each build. Build outputs (DerivedData) are deliberately outside any iCloud-synced location for the same reason.
