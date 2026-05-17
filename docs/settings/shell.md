# Settings -> Shell

The Shell tab controls Loom's terminal integrations: command logging, full
terminal transcripts, and paste behavior.

## Shell Integration

**Capture commands from Loom terminals** is on by default. Loom points zsh at a
small shim under `~/Library/Application Support/Loom Testing Edition/shell/`.
The shim sources your normal zsh config first, then logs command text, cwd,
timing, exit code, session id, and optional captured output to `history.jsonl`.

Turning this off affects new terminal panes. Existing terminals keep the mode
they started with.

## Terminal History

**Save terminal transcripts locally** is on by default in Testing Edition. Loom
records terminal output to local transcript files so closed sessions can be
reviewed later.

| Control | What it does |
| ------- | ------------ |
| Save terminal transcripts locally | Enables or disables new transcript writes. |
| Storage limit | Defaults to 1 GB. Choices are 250 MB, 500 MB, 1 GB, 2 GB, 5 GB, and 10 GB. |
| Currently saved | Shows how much transcript data is on disk right now. |
| Prune Terminal History | Clears saved transcript files. Active terminal panes keep running, but their saved transcript files start over. |
| Reveal History Folder | Opens the local transcript folder in Finder. |

When saved history exceeds the storage limit, Loom prunes old closed/deleted
transcripts first. It does not kill active terminal panes.

## Recently Closed and Recently Deleted

Closed terminal panes appear under **Recently Closed** in the Prompt workspace
sidebar. Click a row to read the transcript, or start a fresh shell in the same
folder from the transcript viewer.

The **Recently Deleted** button at the bottom of Terminal Sessions opens deleted
transcripts. Each deleted transcript can be recovered or deleted permanently.

## Pasting

**Always paste as plain text** sends clipboard text directly into the PTY
instead of SwiftTerm's bracketed paste wrapper. Use it when an interactive tool
renders the bracketed-paste markers literally.

Image-only paste and image drag still insert editable Codex `--image '<path>' `
arguments without pressing Return.

