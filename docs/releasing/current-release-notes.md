## Changes

- Stable Loom is now version 9.0.0 on macOS and Windows, bringing the full Testing Edition feature set into the production channel.
- LM Studio is now a first-class agent provider with saved endpoints, model discovery, readiness checks, load/unload/download controls, run profiles, local tool-loop execution, concise progress, and slash-command workflows.
- Local-model tool calls are more reliable: Loom parses XML-style and fenced tool calls, suppresses raw tool markup from the visible stream, blocks repeated no-result retries, and summarizes before a max-turn stop.
- Terminal transcripts now support Recently Closed restore, Recently Deleted recovery, bounded previews for large sessions, Finder reveal, transcript pruning, and saved raw ANSI history.
- Terminal image handoff now saves pasted or dropped images locally and inserts editable `--image '<path>'` prompt text while preserving text paste priority.
- Mac dictation now streams live speech text into terminal and editor inputs, starts recognition before microphone capture, reports no-speech and no-audio errors clearly, and avoids the Swift 6 mic tap crash.
- Usage dashboards now carry the selected Day, Week, Month, or Year range through the snapshot and show range-specific sessions, tokens, prompts, topics, heatmaps, and Codex limit labels.
- Notes editing now debounces SwiftData saves instead of saving on every keystroke.
- The workspace UI now uses the Mac-style shell, left navigation, block controls, task sessions, usage surfaces, and terminal history workflows across macOS and Windows.
- Live tasks now include Claude, Codex, and LM Studio sessions with model labels, plan activity, clear-one, and clear-all behavior that does not resurrect completed Codex plans after clearing.
- Windows Loom now includes the macOS parity work from Testing Edition: LM Studio model management, terminal transcripts, command cards, image handoff, usage views, settings access, sidebar cleanup, and task-session UI.
- Windows in-app updates now select the highest stable `v*` semver release with a matching versioned installer, verify installer bytes against the embedded Tauri updater public key, and run the NSIS updater arguments with a legacy silent fallback.
- Windows releases now publish signed bridge recovery installers and legacy installer aliases so older installed builds can update forward to Loom 9 even if they still expect older asset names or installer behavior.
- Release metadata, docs, macOS project settings, Windows package settings, updater endpoints, and release scripts now target stable Loom 9.0.0.
