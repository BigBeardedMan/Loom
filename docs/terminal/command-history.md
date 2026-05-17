# Command history

Loom's Commands panel lists every shell command you've run inside a Loom terminal pane: the command itself, its working directory, when it ran, how long it took, and whether it succeeded.

It's available as a panel kind in any **Prompt** workspace. Add it the same way you'd add a Terminal or Editor block.

## How it works

Loom installs a small zsh shim at `~/Library/Application Support/Loom Testing Edition/shell/.zshrc` in the Testing Edition build. When a Loom terminal pane spawns its login shell, the env it passes through includes:

- `ZDOTDIR=~/Library/Application Support/Loom Testing Edition/shell` — points zsh at the shim directory.
- `LOOM_SESSION_ID=<uuid>` — identifies which Loom terminal session ran the command.

The shim's first job is to source your real config (`~/.zshenv`, `~/.zprofile`, `~/.zshrc`, `~/.zlogin`) so nothing about your existing setup changes. After that, it registers `preexec` and `precmd` hooks that write a single JSON line per command to `~/Library/Application Support/Loom Testing Edition/shell/history.jsonl`:

```json
{"started":1778302670,"ended":1778302675,"exit":0,"cwd":"/Users/me/code/foo","command":"git pull","session":"7E3..."}
```

The Commands panel polls this file every 2 seconds via `CommandHistoryService`, parses the most recent records (capped at 500), and renders the list newest-first.

## Workspace filtering

Each row carries the `cwd` it was run from. The panel header has a **Workspace only** checkbox: when on (default), the panel hides commands whose `cwd` isn't inside the workspace's folder. When off, you see every command across every Loom terminal you've ever opened.

## Per-row actions

- **Copy** copies the command text to the macOS pasteboard.
- **Send** (when at least one Terminal block exists in the active workspace) submits the command to the first terminal session as if you'd typed it. Useful for re-running something from an earlier session without retyping.

## Output capture (v2.2.0+)

Commands submitted through Loom's UI (Commands panel **Send**, inline card **Rerun**, ⌘K palette rerun) are wrapped in the shim's `__loom_capture` helper, which tees their stdout+stderr into a per-command file under `~/Library/Application Support/Loom Testing Edition/shell/output/`. The matching JSONL record carries an extra `output` field with the full path.

Hand-typed commands skip this wrapping entirely so interactive TUIs (vim, top, ssh, tmux) keep working unchanged. If you want capture for a hand-typed command, prefix it with `__loom_capture '...'` yourself.

Cards in both the Commands panel and the inline-card terminal view show a chevron when their record has captured output. Click to expand an inline reader (capped at 1 MB, with a truncation notice if exceeded; selectable text for copy-paste).

Exit codes are preserved across the `tee` pipeline via zsh's `pipefail` and `${pipestatus[1]}`.

## What's not captured (yet)

- **Output for hand-typed commands** stays uncaptured by design (TUIs would break). Prefix manually with `__loom_capture '...'` if you want it.
- **Non-zsh shells** are not supported. The shim is zsh-specific. If your `$SHELL` is `bash` or `fish`, the shell still runs normally; nothing breaks, but no commands appear in the panel.
- **Commands run before Loom started writing the shim** (i.e. older zsh sessions or terminals from outside Loom) are not in the log.

## Command history vs. terminal transcripts

Command history is structured metadata: command text, cwd, timing, exit code,
session id, and optional output capture for commands sent through Loom UI.
Terminal transcripts are separate full PTY logs saved under `Terminal History/`
so closed terminal sessions can be reviewed or recovered later.

## Privacy

The history file lives entirely on disk inside Application Support. Nothing leaves your Mac. Loom reads the file with standard `FileManager` calls and does not watch via FSEvents (which would require a separate sandbox entitlement).

## Removing the integration

Use Settings -> Shell and turn off **Capture commands from Loom terminals**.
The change applies to new terminal panes. To remove the existing files, delete
`~/Library/Application Support/Loom Testing Edition/shell/.zshrc` and
`~/Library/Application Support/Loom Testing Edition/shell/history.jsonl`.
Loom recreates the shim on launch, but it is not sourced when the setting is
off.
