# File paths

Where Loom (and the things Loom reads from) keeps state on disk.

## Loom-owned

| Path | Purpose |
| ---- | ------- |
| `~/Library/Application Support/Loom/staging/Loom.app` | Newly downloaded build, waiting for the Update pill click. |
| `~/Library/Application Support/Loom/staging/manifest.json` | `{ version, build, stagedAt }` for the staged build. |
| `~/Library/Application Support/com.chasesims.Loom/default.store` | SwiftData store (workspaces, kanban, notes). Path varies by SwiftData version. |
| `~/Library/Preferences/com.chasesims.Loom.plist` | UserDefaults (theme, stale window, local endpoints). |

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
| `~/Library/Developer/Xcode/DerivedData/Loom-*/Build/Products/Release/Loom.app` | Build output. `release.sh` searches here for the `.app` to package. |
| `<repo>/build/release/Loom-<version>.dmg` | Packaged DMG ready for `gh release upload`. |

## Why Application Support, not the app bundle?

The app bundle is read-only after Gatekeeper-blessing it; SwiftData and the staging directory both need write access. Application Support is the standard macOS location for that. It's also what `~/Library` backups (Time Machine, Carbon Copy) snapshot.

## Why not iCloud Drive?

Two reasons:

1. iCloud renames build artifacts mid-build (`Foo` → `Foo 2`) when sync detects a duplicate, which breaks Xcode and DMG packaging.
2. Loom is single-device by design. There's nothing to sync.

If your clone lives under `~/Documents` (which is iCloud-synced for many users), `project.yml`'s pre-build script defensively sweeps `* 2.*` / `* 3.*` shadow files before each build. Build outputs (DerivedData) are deliberately outside any iCloud-synced location for the same reason.
