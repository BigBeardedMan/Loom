# `lmstudio` CLI

A terminal agent that talks to your local LM Studio server. Same shape as
`claude` or `codex`: type the command, get an interactive agent with a
boxed input, streaming responses, inline thinking, a live task list, and
session save/resume. Tasks land in Loom's Tasks pane automatically.

## Install

```bash
bin/install-lmstudio.sh
```

Symlinks `bin/lmstudio` to `~/.local/bin/lmstudio`. The script prints a
`PATH` hint if needed. No sudo, no `pip install` — stdlib Python only.

## One-time setup

1. Start LM Studio's local server: **LM Studio → Developer → Local Server → Start** (default port `1234`).
2. Load a model in Chat (or `lms load <id>` if you have the LM Studio CLI installed).
3. Run `lmstudio` — it auto-discovers the loaded model via `/api/v0/models`. No need to look up an identifier.

If you have multiple models loaded, the CLI lists them and asks you to pin one with `--model` or `LMSTUDIO_MODEL`.

## Usage

```bash
lmstudio                              # interactive REPL
lmstudio "refactor the parser"        # one-shot
lmstudio --allow-bash "fix this test" # enable run_bash for this session
lmstudio --resume                     # resume the most recent session
lmstudio --theme cyberpunk            # alt palette
lmstudio --json "..."                 # structured event stream (scripting)
```

The CLI runs in the current working directory. Tool paths are resolved relative to it; the runner refuses to read or write outside.

## Slash commands

Type these at the `❯` prompt (they don't go to the model):

| Command | Effect |
| --- | --- |
| `/help` | Show tips and the full command list |
| `/clear` | Reset the transcript (history file kept) |
| `/model` | List loaded models. `/model <id>` swaps mid-session |
| `/bash [on\|off]` | Toggle the `run_bash` tool |
| `/cwd [path]` | Show or change the workspace root (reloads project context + knowledge) |
| `/cost` | Approximate token count, elapsed wall-clock, tok/s |
| `/tasks` | Re-render the current task list |
| `/save [name]` | Save the session to `~/.loom/sessions/<name>.json` |
| `/resume [name]` | Load a saved session (most recent if no name) |
| `/sessions` | List saved sessions |
| `/system <text>` | Override the system prompt and reset the transcript |
| `/sh <cmd>` | Run a shell command yourself (no agent involved) |
| `/yolo [on\|off]` | Toggle permission prompts off (use with care) |
| `/theme <name>` | Switch palette (default, mono, cyberpunk, solarized) |
| `/wrap [on\|off]` | Toggle word-boundary wrapping |
| `/auto [on\|off\|N]` | Toggle / set continuation budget |
| `/compact [on\|off\|now]` | Toggle auto-compaction or force it right now |
| `/undo`, `/undo all` | Roll back the last (or all) write_file/edit_file/multi_edit |
| `/journal` | List every fs mutation this session with line counts |
| `/diff session` | Print the aggregate unified diff for the session |
| `/test [on\|off]` | Toggle auto-test runner after fs mutations |
| `/recall <query>` | Search tool-result memory for a keyword/phrase |
| `/preview [on\|off\|url]` | Spin up / stop the live HTTP preview |
| `/branch <name>` | Snapshot the current transcript + tasks + journal as a branch |
| `/checkout <name>` | Swap to a saved branch (current state stays at its own branch) |
| `/branches` | List branches |
| `/merge <name>` | Pull the last assistant message + tasks of `<name>` into context |
| `/router <planner\|coder\|explainer> <model>` | Set a per-role model. `/router off` clears |
| `/prefetch [on\|off]` | Toggle speculative tool prefetch |
| `/quit`, `/exit` | Leave the REPL (writes `.loom/project.json`) |

## Built-in tools

| Tool | What it does |
| --- | --- |
| `read_file(path)` | UTF-8 file read; cached for the session (memory + prefetch) |
| `write_file(path, content)` | Create/overwrite. Journaled for `/undo`. Syntax-checked when the extension is known |
| `edit_file(path, old, new)` | Single-substring replace. Journaled + syntax-checked |
| `multi_edit(path, edits)` | N replacements in one call. Errors out on first old_string not found, naming the index |
| `list_dir(path)` | Directory listing |
| `glob(pattern, path?)` | Workspace-rooted glob (supports `**`). Cap 200 hits |
| `grep(pattern, path?, include?)` | `grep -rIn`. Cap 200 lines |
| `run_bash(command, timeout?)` | Shell in a fresh session id. Gated by `--allow-bash` or `/bash on` |
| `update_tasks(tasks)` | Replace the task list. Subjects naming a file are verified on disk — claims without the artifact get flipped back to `in_progress` |
| `spawn_agent(prompt, role?, system?)` | Delegate a focused subtask to a child `lmstudio --json` process |

## @file mentions + tab completion

Type `@path/to/file` in your message to inline that file's contents:

```
❯ refactor @src/parser.py to use pathlib
```

The CLI rewrites the prompt to include a tagged `<file path="...">…</file>` block before sending. Tab completes paths from the workspace; for slash commands it completes the command name.

### Media types

`@file` understands more than just text:

- **Images** (`.png .jpg .jpeg .heic .webp .tiff .bmp`) — macOS Vision OCR via `osascript`. Returns the recognized text as `<file type="image-ocr">`.
- **PDFs** (`.pdf`) — `pdftotext` (Homebrew Poppler) when present, with a `mdimport` fallback that pulls `kMDItemTextContent` out of Spotlight.
- **Audio** (`.m4a .wav .mp3 .flac .aac`) — local `whisper.cpp` if installed at `~/whisper.cpp/build/bin/whisper-cli`. Falls back to a `<file type="audio"/>` placeholder.
- **Other binaries** — `<file type="binary" size="N"/>` placeholder so the model knows the file exists.

## Permission prompts

Before `write_file`, `edit_file`, or `run_bash` execute, the CLI asks:

```
  ⚠ Allow write_file src/parser.py?
  [y] yes once   [n] no   [a] yes (always this session)
  → █
```

Answer `a` to allow that tool for the rest of the session. `--yolo` (or `LMSTUDIO_YOLO=1`, or `/yolo on`) disables prompts entirely.

## Auto-loaded project context

On launch (and after `/cwd <path>`), the CLI reads `CLAUDE.md`, `AGENTS.md`, `GUIDE.md`, and `README.md` from the workspace in priority order, concatenates up to ~5 KB total, and appends them to the system prompt under a `# Project Context` heading. Disable with `--no-context`.

## Pre-flight workspace scan

Also on launch (and after `/cwd`), the CLI does a single shallow walk of the workspace (depth 3, capped at 200 entries) and injects a `# Workspace Layout` block into the system prompt. Hidden dirs and the usual noise (`node_modules`, `__pycache__`, `.venv`, `DerivedData`, `dist`, `build`, `Pods`, etc.) are skipped. The banner shows `tree N entries` so you can see what the model received.

The point is to stop local models from spending their first 5 turns calling `list_dir` to orient themselves. The orchestrator's path-repair also has more material to match against — when the model says "I'll create `index.html`," we know which directory to put it in. Skipped entirely under `--no-context`.

## Grammar-constrained tool calls

When the active LM Studio server speaks `response_format: json_schema` (probed at session start with a 10s ping), the orchestrator gains a final-fallback move: if a tool call comes in with required arguments still missing **after** narration repair, the CLI makes a one-shot non-streaming completion to that same server with `tool_choice` pinned to the failing tool and the tool's parameter schema as a strict `json_schema`. The server-side decoder refuses to emit JSON that violates the schema, so a successful return is guaranteed to have every required field. The dispatched tool runs with the grammar-filled args and the result is annotated `[orchestrator: grammar-filled \`path\`, \`content\`]` so you can see exactly what the model originally dropped.

The banner shows `grammar on (json_schema)` when supported. Backends that don't accept `response_format` (older OpenAI-compat servers, some MLX kernels) silently fall back to today's repair-only behavior. Force-disable with `LMSTUDIO_NO_GRAMMAR=1` to compare the two paths side-by-side.

## Inline diffs

After `write_file` or `edit_file`, a unified diff renders right in the shell so you can see exactly what changed. Capped at 12 visible lines plus a `…N more` footer when longer.

## Save / resume

`/save demo` dumps the transcript + tasks + model + cwd to `~/.loom/sessions/demo.json`. `lmstudio --resume demo` (or just `--resume` for the latest) reloads it on launch. `/sessions` lists what's available.

## Themes

`--theme default | mono | cyberpunk | solarized`. `mono` strips ANSI codes entirely; useful for logs, pipes, or terminals that mangle escape sequences. `NO_COLOR=1` forces mono regardless of flag.

## Status footer + boxed input

A one-line footer above each prompt shows model, cwd, approximate tokens, elapsed time, and bash state. The input itself is wrapped in a cyan box (Claude-Code style) — top and bottom borders rendered around the readline prompt.

## History + key bindings

- `↑` / `↓` — walk through previous prompts
- `Ctrl-R` — reverse history search
- `Ctrl-A` / `Ctrl-E` — line start / end (standard readline)
- `Esc` — interrupt the running turn (drops you back at the prompt with transcript intact)
- `Ctrl-D` — exit

History persists at `~/.config/loom/lmstudio-history` (1000 entries).

## Subagent dispatch

The model can call a `spawn_agent(prompt, role?, system?)` tool to delegate a focused subtask. Under the hood this launches `lmstudio --json` as a subprocess with the role string folded into its system prompt and returns the child's final answer. Useful for "research this codebase" or "draft tests for this function" without bloating the parent transcript.

## MCP servers

Connect a Model Context Protocol server with `--mcp "<command>"`. The CLI runs the JSON-RPC `initialize` + `tools/list` handshake on stdio, then exposes every advertised tool to the model with an `mcp__` prefix. Repeatable:

```bash
lmstudio --mcp "node my-mcp-server.js" --mcp "uvx some-other-server"
```

This is a minimal client — `initialize`, `tools/list`, `tools/call`. No resources, prompts, or sampling.

## JSON output mode

`lmstudio --json` emits one JSON event per line instead of styled text. Event types: `session_started`, `turn_started`, `content`, `thinking`, `tool_call`, `tool_result`, `completed`, `error`, `interrupted`, `session_ended`. Stdin reads newline-delimited prompts. Useful for piping into other tooling or scripting on top of the agent loop.

## Task tracking + verification

Every `update_tasks` call writes one JSON file per task to `~/.loom/tasks/<session-id>/<task-id>.json` in Claude's shape. `LiveAgentTasksService` polls that directory every 2 seconds and surfaces sessions under the **lmstudio** source in Loom's Tasks pane.

When the model flips a task to `completed`, the orchestrator inspects the subject for a file mention (`"Create index.html"`, `"Add styles.css"`). If the named file doesn't exist (or is zero bytes), the task is rewritten to `in_progress` and the model is told what's missing on the next turn. Subjects with no path inference (`"research X"`, `"design Y"`) skip verification.

## Auto-compaction

When `approx_tokens / context_window` exceeds 75%, the CLI sends a one-shot summarization prompt to the model, replaces the middle of the transcript with the summary, and continues. The system message and the last ~6 turns are preserved. The footer shows `compacted Nx`. Toggle with `/compact on|off`; force a manual compaction with `/compact now`.

## Speculative tool prefetch

As the model streams its narration, the CLI scans for file mentions and fires off `read_file` requests in the background. When the model emits the formal `read_file` tool call a moment later, the result returns instantly from cache. Cache TTL is 30s. Stats (hits / misses) shown in `/prefetch`. Disable with `--no-prefetch` or `/prefetch off`.

## Parallel tool execution

When the model emits multiple tool calls in one assistant turn, the safe read-only ones (`read_file`, `list_dir`, `glob`, `grep`) run concurrently through a 4-worker thread pool. Mutating tools (`write_file`, `edit_file`, `multi_edit`, `run_bash`) run sequentially so writes are deterministic and permission prompts don't stack. Results are re-sorted into the model's original call order before being appended to the transcript.

## Self-healing syntax checks

After every successful `write_file`, `edit_file`, or `multi_edit`, the CLI runs a content validator keyed off file extension:

- `.py` → `ast.parse`
- `.json` → `json.loads`
- `.html`/`.htm` → `html.parser`
- `.yml`/`.yaml` → `yaml.safe_load` if PyYAML is installed
- `.js / .ts / .jsx / .tsx / .css / .scss / .swift / .rs / .go / .c / .cpp / .java` → cheap brace + quote balance check

If validation fails, the tool result tells the model what broke. The file remains on disk so `/undo` can roll it back if needed.

## Undo journal

Every `write_file`, `edit_file`, or `multi_edit` snapshots `(path, prior, new, ts)` into the journal. The journal is also appended to `~/.loom/journal/<session-id>.jsonl` so a crashed CLI can be recovered.

- `/undo` — pop the latest entry, restore the prior content (or delete the file when prior is empty).
- `/undo all` — roll back every mutation in reverse order.
- `/journal` — list all mutations with line-delta counts.
- `/diff session` — render the aggregate unified diff for the session.

## Auto-test integration

With `--auto-test` (or `/test on`), the CLI auto-runs the workspace's test framework after any turn that mutated a test file. Framework detection walks the workspace for the obvious markers:

- `pyproject.toml` / `pytest.ini` → `pytest -x --no-header`
- `package.json` with a `test` script → `npm test`
- `Package.swift` → `swift test --quiet`
- `Cargo.toml` → `cargo test --quiet`
- `go.mod` → `go test ./...`

Test failures (last 30 lines) are fed back to the model as a synthetic system message so it can self-correct without you having to copy-paste a stack trace.

## Tool result memory + recall

Every tool result lands in a session-scoped TF-IDF index (cheap stdlib `Counter` over alphanumeric tokens). `/recall <query>` searches the index and surfaces the top 3 matches with snippets. This is the cheap version of RAG: when you remember "we already saw this in some file," type `/recall foo` instead of re-reading. Bounded at 200 entries (oldest evicted).

## Project knowledge layer

On session start, the CLI reads `<workspace>/.loom/project.json` if it exists and injects it into the system prompt under `# Project Knowledge`. On clean quit, it writes back an enriched version with:

- A rolling summary (the last assistant message, capped at 2 KB)
- The bash commands you ran successfully this session
- A `last_updated` timestamp

The third session in the same workspace is dramatically smarter than the first — the model already knows your build command, the test runner, and what was done last time. Skip the load with `--no-context`.

## Live preview server

`/preview on` (or with `index.html` in the workspace and a banner-prompt acceptance) spins up `http.server` on a free port bound to `127.0.0.1` and shows the URL in the banner. The browser is **never** auto-opened. Stop with `/preview off`. The server thread is daemon-ed and torn down on `/quit`.

## Conversation branching

Branches are full transcript snapshots (transcript + tasks + journal + token count) saved to `~/.loom/branches/<name>.json`.

- `/branch <name>` — snapshot now.
- `/checkout <name>` — swap to a branch.
- `/branches` — list with token / task counts.
- `/merge <name>` — pull the last assistant message + task list of another branch into the current transcript as a context note.

Useful for "what if I told it to use JWT instead of sessions" comparisons without losing the original state.

## Multi-model routing

Set per-role model overrides with CLI flags or env vars:

- `--planner-model` / `LMSTUDIO_PLANNER_MODEL` — fast, small (3-7B); used when the user message looks plan-y (`plan`, `design`, `outline`).
- `--coder-model` / `LMSTUDIO_CODER_MODEL` — focused coder (14-32B coder).
- `--explainer-model` / `LMSTUDIO_EXPLAINER_MODEL` — articulate, large; used for `explain`/`why`/`summarize`.

`/router planner <id>` swaps the planner mid-session. `/router off` clears all overrides. Requires LM Studio to have the relevant models loaded (or JIT-loaded on demand).

## Model recommendations

Tool-calling collapses on small or non-coder models. Reliable picks:

- Qwen2.5-Coder 7B / 14B Instruct
- DeepSeek-Coder-V2-Lite-Instruct
- Llama 3.1 70B Instruct (with the VRAM)

General-purpose 3B–4B models will usually skip `update_tasks` or call it once and forget.

## Troubleshooting

**"Could not reach LM Studio at http://localhost:1234/v1"** — server isn't running. Start it from the LM Studio app, or `lms server start --port 1234`.

**"multiple models loaded"** — pass `--model` or set `LMSTUDIO_MODEL`. `/model` in the REPL lists what's loaded.

**Box drawing looks broken after resizing the terminal** — boxes recompute width on each new prompt, so the next turn after a resize renders cleanly. The in-flight box on the line you resized over stays at its original width until you submit.

**Tasks aren't appearing in Loom's Tasks pane** — confirm Loom is running and Settings → Tasks "Stale window" isn't set so tight the session is being hidden. Check `~/.loom/tasks/<session>/`; if files are there, the pickup is on Loom's side.
