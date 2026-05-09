# Command history

Loom's Commands panel lists every shell command you've run inside a Loom terminal pane: the command itself, its working directory, when it ran, how long it took, and whether it succeeded.

It's available as a panel kind in any **Prompt** workspace. Add it the same way you'd add a Terminal or Editor block.

## How it works

Loom installs a small zsh shim at `~/Library/Application Support/Loom/shell/.zshrc`. When a Loom terminal pane spawns its login shell, the env it passes through includes:

- `ZDOTDIR=~/Library/Application Support/Loom/shell` — points zsh at the shim directory.
- `LOOM_SESSION_ID=<uuid>` — identifies which Loom terminal session ran the command.

The shim's first job is to source your real config (`~/.zshenv`, `~/.zprofile`, `~/.zshrc`, `~/.zlogin`) so nothing about your existing setup changes. After that, it registers `preexec` and `precmd` hooks that write a single JSON line per command to `~/Library/Application Support/Loom/shell/history.jsonl`:

```json
{"started":1778302670,"ended":1778302675,"exit":0,"cwd":"/Users/me/code/foo","command":"git pull","session":"7E3..."}
```

The Commands panel polls this file every 2 seconds via `CommandHistoryService`, parses the most recent records (capped at 500), and renders the list newest-first.

## Workspace filtering

Each row carries the `cwd` it was run from. The panel header has a **Workspace only** checkbox: when on (default), the panel hides commands whose `cwd` isn't inside the workspace's folder. When off, you see every command across every Loom terminal you've ever opened.

## Per-row actions

- **Copy** copies the command text to the macOS pasteboard.
- **Send** (when at least one Terminal block exists in the active workspace) submits the command to the first terminal session as if you'd typed it. Useful for re-running something from an earlier session without retyping.

## What's not captured (yet)

- **Output** is not captured. Output capture without breaking interactive TUIs (vim, top, ssh) needs a `script`-style PTY tee, which is a future expansion.
- **Non-zsh shells** are not supported. The shim is zsh-specific. If your `$SHELL` is `bash` or `fish`, the shell still runs normally; nothing breaks, but no commands appear in the panel.
- **Commands run before Loom started writing the shim** (i.e. older zsh sessions or terminals from outside Loom) are not in the log.

## Privacy

The history file lives entirely on disk inside Application Support. Nothing leaves your Mac. Loom reads the file with standard `FileManager` calls and does not watch via FSEvents (which would require a separate sandbox entitlement).

## Removing the integration

Delete `~/Library/Application Support/Loom/shell/.zshrc`. Loom will re-create it on next launch unless you also turn off the integration (planned for a future Settings tab). To stop new entries from being logged in the meantime, delete the history file: `~/Library/Application Support/Loom/shell/history.jsonl`. The file is recreated on the next command if the shim is still in place.
