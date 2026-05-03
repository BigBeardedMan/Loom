# Terminal

Loom's Terminal pane is a real terminal, backed by [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm). It runs your login shell with a TTY, so interactive tools (Vim, top, fzf, ssh sessions) work the same as they do in iTerm.

## What it ships with

- Login shell (`/bin/zsh -l` by default; respects `$SHELL`).
- TTY allocation (so things like `top` and `bat` get a width).
- Working directory seeded from the workspace folder.
- Standard ANSI color and 256-color support; truecolor via SwiftTerm.

## What it doesn't have (yet)

- **Command-block history** — every shell command becomes its own scrollable, copyable card. On the roadmap; today the pane is a flat scrollback like a normal terminal.
- **Multi-pane terminal layouts** (split panes inside one Terminal pane) — also on the roadmap. Today, add multiple Terminal panes to the workspace and pin them.
- **Built-in SSH session manager** — out of scope. Use `ssh` like normal.

## Working directory

The terminal launches in the workspace's folder URL. Subsequent `cd`s persist within the session. Restart the pane (× then re-add) to reset to the workspace folder.

## Copy / paste

Standard macOS shortcuts: ⌘C copies the selection, ⌘V pastes. Selection works with mouse drag. There's no "select rectangle" mode today.

## Scrollback

SwiftTerm keeps the default 1000-line scrollback. Scroll with two-finger drag or the keyboard's Page Up / Page Down (depending on terminal app's `terminfo`).

## The terminal as the differentiator

Loom's product principle: **terminal work should be reviewable**. Today that means giving the terminal first-class real-estate alongside the editor and agent. As Loom evolves the terminal will accumulate structure — command boundaries, exit codes, agent-issued vs human-issued commands — that other tools throw away as scrollback.
