# Windows/macOS Parity Task List for 8.2.67

## Scope

This checklist tracks the Windows Testing Edition parity pass against the current macOS Loom implementation for terminal history, task sessions, sidebar workflows, command capture, image handoff, settings, and version metadata.

## Inventory

- [x] Compare Windows terminal pane behavior against `Loom/Terminal/TerminalPaneView.swift`.
- [x] Compare Windows terminal session behavior against `Loom/Terminal/TerminalSession.swift`.
- [x] Compare Windows transcript persistence against `Loom/Terminal/TerminalTranscriptStore.swift`.
- [x] Compare Windows command history behavior against `Loom/Terminal/CommandHistoryPaneView.swift`.
- [x] Compare Windows shell integration against `Loom/Terminal/ShellIntegration.swift`.
- [x] Compare Windows workspace layout behavior against `Loom/Workspace/WorkspaceLayout.swift`.
- [x] Compare Windows sidebar behavior against `Loom/Workspace/WorkspaceSidebarView.swift`.
- [x] Compare Windows task pane behavior against `Loom/Kanban/KanbanPaneView.swift`.
- [x] Compare Windows live task collection against `Loom/Agents/LiveAgentTasks.swift`.
- [x] Compare Windows shell settings against `Loom/Settings/SettingsScene.swift`.
- [x] Preserve existing Windows-only updater, tray, and shell surfaces while adding parity behavior.

## Terminal Transcripts

- [x] Add a Rust transcript store for Windows PTY output.
- [x] Store transcript metadata in app data under `Terminal History`.
- [x] Store raw terminal output separately from metadata.
- [x] Track transcript states for open, closed, and deleted sessions.
- [x] Track workspace id, workspace name, title, cwd, shell, pid, created time, updated time, byte count, and exit code.
- [x] Append raw PTY bytes to the active transcript.
- [x] Close transcripts when PTY reader reaches EOF.
- [x] Close transcripts when a wait thread observes process exit.
- [x] Close transcripts when the user kills a terminal.
- [x] Keep terminal metadata current when title or cwd changes.
- [x] Add bounded transcript preview reads for sidebar modals.
- [x] Add bounded transcript restore reads for reopened terminal panes.
- [x] Include trim metadata when a restore is capped.
- [x] Add Recently Closed listing by workspace.
- [x] Add Recently Deleted listing by workspace.
- [x] Add restore from Recently Closed.
- [x] Add move to Recently Deleted.
- [x] Add recover from Recently Deleted.
- [x] Add permanent delete for transcript files and metadata.
- [x] Add transcript pruning based on storage limit.
- [x] Add transcript enable/disable configuration.
- [x] Add transcript folder reveal support.
- [x] Expose all transcript operations through Tauri commands.
- [x] Expose all transcript operations through TypeScript IPC.

## Terminal Restore UX

- [x] Allow a workspace layout block to carry a transient restored transcript payload.
- [x] Strip transient restore payloads before layout persistence.
- [x] Add a store action to reopen a terminal block from a transcript restore.
- [x] Spawn restored terminals with the original session id.
- [x] Spawn restored terminals with the original cwd when available.
- [x] Spawn restored terminals with the original title.
- [x] Feed restored scrollback into xterm after session startup.
- [x] Add a visible restored-session header before imported scrollback.
- [x] Add a trim notice when restored scrollback was capped.
- [x] Keep restored transcript data out of future saved layouts.

## Sidebar Parity

- [x] Replace the old Windows sidebar session list with macOS-style workspace sections.
- [x] Show Ideas workspace notes in the sidebar.
- [x] Support idea rename.
- [x] Support idea delete.
- [x] Support clear-all ideas for the selected workspace.
- [x] Show Review workspace placeholder content.
- [x] Show terminal blocks for Code workspaces.
- [x] Show terminal block custom titles.
- [x] Support terminal block rename from the sidebar.
- [x] Support terminal block close from the sidebar.
- [x] Support close-all terminal blocks from the sidebar.
- [x] Show Recently Closed transcripts in Code workspaces.
- [x] Show Recently Deleted transcripts in Code workspaces.
- [x] Add Recently Deleted toggle.
- [x] Add transcript preview modal.
- [x] Add transcript restore from preview.
- [x] Add transcript folder reveal from preview.
- [x] Add move-to-deleted action for closed transcripts.
- [x] Add recover action for deleted transcripts.
- [x] Add permanent delete action for deleted transcripts.
- [x] Keep usage tool switching intact in the left rail.

## Command History and Capture

- [x] Add terminal session id to PowerShell command records.
- [x] Add terminal session id to Rust command history records.
- [x] Add terminal session id to TypeScript command history types.
- [x] Preserve output path capture in history records.
- [x] Add command output expansion in the command history pane.
- [x] Add captured output loading through existing IPC.
- [x] Change send-to-terminal from plain rerun to capture-aware rerun.
- [x] Escape PowerShell capture commands safely.
- [x] Add per-terminal inline command cards.
- [x] Filter inline command cards by terminal session id.
- [x] Add inline command-card output expansion.
- [x] Add inline command-card copy.
- [x] Add inline command-card capture-aware rerun.
- [x] Add a terminal header toggle for inline command cards.

## Image Handoff and Prompt Editing

- [x] Enable clipboard image reads in Windows Tauri capabilities.
- [x] Preserve text paste as the winner when text and images are both present.
- [x] Read clipboard images through `@tauri-apps/plugin-clipboard-manager`.
- [x] Convert clipboard RGBA image data to PNG.
- [x] Save pasted images under app data `Clipboard Images`.
- [x] Insert editable `--image '<path>'` text into the terminal prompt.
- [x] Use PowerShell-safe single-quote escaping for image paths.
- [x] Support image file drag and drop.
- [x] Support raw image drag and drop.
- [x] Keep drag and drop from navigating the webview.
- [x] Preserve click-to-position prompt editing.
- [x] Keep click-to-position available across Claude, Codex, Gemini, LM Studio, and plain shell prompts where the shell accepts cursor movement.

## Live Tasks

- [x] Add model labels to live task records.
- [x] Add model labels to live task groups.
- [x] Match macOS group identity with source, model key, and session id.
- [x] Read Claude task files from `~/.claude/tasks`.
- [x] Read Claude model labels from `~/.claude/projects`.
- [x] Read Codex plan updates from `~/.codex/sessions`.
- [x] Read Codex model labels from rollout `turn_context` records.
- [x] Use Codex plan timestamps for task activity instead of only file mtime.
- [x] Hide completed-only Codex rollouts.
- [x] Read LM Studio CLI task files from `~/.loom/tasks`.
- [x] Keep Gemini, Ollama, and OpenAI-compatible source shapes available in the frontend type model.
- [x] Sort task groups by latest activity.
- [x] Sort tasks by in-progress, pending, completed, cancelled, then updated time.
- [x] Persist dismissed task sessions in app data.
- [x] Delete file-backed Claude task JSON when clearing a Claude group.
- [x] Delete file-backed LM Studio task JSON when clearing an LM Studio group.
- [x] Hide log-backed Codex sessions until their plan updates.
- [x] Add clear-one-session command.
- [x] Add clear-all-sessions command.
- [x] Render Windows Tasks as the macOS list-style session view.
- [x] Show source icon, source label, model label, session prefix, headline, and task count.
- [x] Show task status icons and status labels.
- [x] Add refresh action.
- [x] Add clear group action.
- [x] Add clear all action.

## Settings

- [x] Add terminal history status to Shell settings.
- [x] Add local transcript save toggle.
- [x] Add storage limit control.
- [x] Show current saved transcript bytes.
- [x] Add prune-now action.
- [x] Add reveal history folder action.
- [x] Keep active terminal panes running when transcript settings change.

## Layout and Defaults

- [x] Match the macOS default Code workspace layout with terminal, tasks, and agent blocks.
- [x] Preserve existing custom block title behavior.
- [x] Preserve terminal split count and split axis behavior.
- [x] Keep restored transcript payloads transient.
- [x] Keep workspace layout saves compatible with older Windows records.

## Versioning and Notes

- [x] Bump macOS Testing Edition marketing version to 8.2.67.
- [x] Bump macOS Testing Edition build number to 67.
- [x] Bump Windows package version to 8.2.67.
- [x] Bump Windows Cargo crate version to 8.2.67.
- [x] Bump Windows Tauri bundle version to 8.2.67.
- [x] Bump Windows Cargo lock package version to 8.2.67.
- [x] Update release notes for Windows/macOS parity.
- [x] Add this parity task list to the repo.

## Verification

- [x] Run TypeScript compile check with `pnpm --dir windows-tauri lint`.
- [x] Run Windows frontend production build with `pnpm --dir windows-tauri build`.
- [x] Run Rust compile check with `cargo check --manifest-path windows-tauri/src-tauri/Cargo.toml`.
- [x] Re-run TypeScript after task pane IPC and type changes.
- [x] Re-run Rust after live task backend changes.
- [x] Regenerate the ignored local Xcode project with `xcodegen generate`.
- [x] Run macOS Debug build with full Xcode and signing disabled.
- [x] Verify built macOS `Info.plist` reports `CFBundleShortVersionString = 8.2.67` and `CFBundleVersion = 67`.
- [x] Confirm version metadata no longer reports 8.1.10 or 8.2.0 in primary version files.
- [x] Remove accidental formatting churn from unrelated Rust modules.

## Verification Notes

- Windows-target Rust checks were attempted for `x86_64-pc-windows-msvc` and `aarch64-pc-windows-msvc` using rustup cargo. Both stopped in the `ring` build script because this Mac does not have the Windows C headers/toolchain needed for cross-compiling MSVC targets (`assert.h` missing). The host Rust check, Windows frontend production build, and macOS Debug build all passed locally.
