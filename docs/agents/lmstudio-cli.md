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
| `/doctor` | Check LM Studio install, `lms` CLI, server, loaded models, context, grammar, and tool support |
| `/server status\|start\|stop\|daemon` | Manage the LM Studio local server from the shell |
| `/status` | Show the current session, model, mode, permissions, routing, context, and background shells |
| `/commands` | Show slash commands grouped by workflow, including custom `.loom/commands/*.md` files |
| `/help [command]` | Show tips and command help |
| `/clear` | Reset the transcript (history file kept) |
| `/model` | List loaded models. `/model <id>` swaps mid-session |
| `/models` | List local LM Studio models on disk with loaded/tool-use markers |
| `/model-info` | Show model adapter, tool, grammar, and context details |
| `/load <id> [context]` | Load a model through `lms load` |
| `/unload [id]` | Unload a model through `lms unload` |
| `/autoscale <target\|max>` | Reload the active model with a larger context target |
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
| `/screenshot [on\|off]` | Toggle auto-screenshot on UI mutations |
| `/batch [on\|off]` | Toggle aggressive multi-step batching |
| `/autocommit [on\|off]` | Toggle git auto-commit on task completion |
| `/persona [name]` | Load a persona by name (or print current) |
| `/lsp <command>`, `/lsp off` | Start/stop an LSP server (stdio JSON-RPC) |
| `/install`, `/install run` | Show or update the `~/.local/bin/lmstudio` symlink |
| `/quit`, `/exit` | Leave the REPL (writes `.loom/project.json` + persists permissions) |

## Built-in tools (7.0.0 — 57 tools)

Internet:
- `web_search(query, limit?)` — DuckDuckGo HTML scrape
- `web_fetch(url, mode?)` — HTTP GET + readability strip
- `http_request(method, url, headers?, body?, timeout?)` — arbitrary REST (permission-gated)
- `rss_fetch(url, limit?)` — parse RSS/Atom
- `websocket_subscribe(url, message?, until?, timeout?)` — RFC6455 minimal client (permission-gated)

GitHub workflow:
- `gh_create_pr(title, body?, base?, draft?)`, `gh_pr_view(number?)`, `gh_pr_comment(number, body)`
- `gh_issue_list(state?, label?, limit?)`, `gh_issue_create(title, body?, label?)`, `gh_issue_view(number)`

Communication (macOS):
- `slack_post(webhook_url, text, channel?)` (permission-gated)
- `imessage_send(recipient, body)` (permission-gated)
- `mail_send(to, subject, body)` (permission-gated)

Databases:
- `sqlite_query(database, sql, params?, allow_mutation?)`, `sqlite_schema(database, table?)`
- `postgres_query(sql, conn_string?, allow_mutation?)`, `mysql_query(sql, conn_string?, allow_mutation?)`
- `redis_query(command, host?)`

macOS-native:
- `keychain_get(service, account?)`, `mdfind(query, path?)`
- `notes_create(title, body)`, `notes_search(query)`
- `calendar_today()`, `calendar_create(title, when, duration?)`
- `screen_capture_region()`

Symbol intelligence + dependencies:
- `symbol_search(query, kind?)` — ctags or regex fallback
- `package_list()`, `package_install(name, version?, manager?)`

Sandboxed code execution:
- `exec_python(code, timeout?)`, `exec_js(code, timeout?)`

Meta:
- `ship_it(spec, target?)` — plan → scaffold → test → commit → PR end-to-end

(See earlier sections for the rest: read/write/edit/multi_edit, glob/grep, list_dir, find_todos, git_*, browser_*, lsp_*, run_bash, update_tasks, spawn_agent.)

## Built-in tools (legacy table)

| Tool | What it does |
| --- | --- |
| `read_file(path)` | UTF-8 file read; cached for the session (memory + prefetch) |
| `write_file(path, content)` | Create/overwrite. Journaled for `/undo`. Syntax-checked when the extension is known |
| `edit_file(path, old, new)` | Single-substring replace. Journaled + syntax-checked |
| `multi_edit(path, edits)` | N replacements in one call. Errors out on first old_string not found, naming the index |
| `list_dir(path)` | Directory listing |
| `glob(pattern, path?)` | Workspace-rooted glob (supports `**`). Cap 200 hits |
| `grep(pattern, path?, include?)` | `grep -rIn`. Cap 200 lines |
| `find_todos(pattern?, path?)` | Find TODO/FIXME/XXX/HACK/NOTE markers across the workspace |
| `git_status` | `git status --short --branch` |
| `git_diff(path?, staged?)` | `git diff` working tree (or staged) |
| `git_log(limit?)` | `git log --oneline -N` (default 20, max 200) |
| `git_blame(path)` | `git blame` for a single file |
| `git_show(commit?)` | `git show --stat`, defaults to HEAD |
| `browser_open(url)` | Open or navigate the headless Chromium to a URL |
| `browser_screenshot(path?, full_page?)` | Screenshot the current page (default: full page into `screenshots/`) |
| `browser_click(selector)` | Click an element by CSS selector |
| `browser_type(selector, text)` | Fill a form field |
| `browser_eval(script)` | Run a JS expression, return the result |
| `browser_text` | Inner text of the current page |
| `browser_close` | Tear down the browser subprocess |
| `lsp_diagnostics(path)` | LSP diagnostics for a file (requires `--lsp`) |
| `lsp_definition(path, line, character)` | LSP go-to-definition |
| `lsp_references(path, line, character)` | LSP find-references |
| `run_bash(command, timeout?)` | Shell in a fresh session id. Output streams live to the terminal so long commands aren't silent. Gated by `--allow-bash` or `/bash on` |
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

## Git intelligence

Five built-in tools shell out to `git` for repo awareness without going through `run_bash`:

- `git_status` / `git_diff(path?, staged?)` / `git_log(limit?)` / `git_blame(path)` / `git_show(commit?)`

All run with output capped (32 KB for diff/log, 20 KB for blame/show, 16 KB everywhere else). All are in `SAFE_PARALLEL_TOOLS`, so the model can fan out `git_status + git_diff + git_log` in one turn.

### Auto-commit

`--auto-commit` (or `/autocommit on`) stages everything and commits with an auto-generated message keyed off the most recently completed task whenever the task list flips a task to `completed`. Workspace must be a git repo; failures are silent (no half-staged state).

## Browser automation

When `playwright` is importable from the local Python and Chromium is installed (`python -m playwright install chromium`), the agent gets seven built-in browser tools driven by a persistent subprocess speaking JSON over stdin/stdout:

- `browser_open(url)` — `page.goto`, returns `{url, title}`.
- `browser_screenshot(path?, full_page?)` — saves to `path` (default `screenshots/shot-<ts>.png`).
- `browser_click(selector)` / `browser_type(selector, text)` — interact with the page.
- `browser_eval(script)` — run a JS expression and return the result.
- `browser_text` — inner text of the current page (cap 32 KB).
- `browser_close` — tear down.

The subprocess is lazy-launched on the first `browser_*` call and torn down on `/quit`. When Playwright isn't installed, the tool returns a clear error pointing at the install command.

### Auto-screenshot on UI edits

`--auto-screenshot` (or `/screenshot on`) closes the loop on web work. After any `write_file` / `edit_file` / `multi_edit` to a `.html / .htm / .css / .scss / .jsx / .tsx / .svelte` file, the orchestrator:

1. Starts the preview server (if not running already).
2. Navigates the headless browser to the URL.
3. Screenshots full-page into `screenshots/auto-<ts>.png`.
4. OCRs the screenshot via macOS Vision.
5. Feeds the OCR text back as a synthetic system message so the model can verify the render visually without you asking it to.

## Streaming `run_bash`

`run_bash` now uses `Popen` instead of `subprocess.run`. The combined stdout/stderr is line-streamed to the terminal as the command runs (prefixed with a dim `│`), so long-running tasks (`npm install`, `swift build`) are no longer silent. The full output (capped at 32 KB) is still returned as the tool result so the model sees everything. Timeout default raised from 30s to 30s with a 600s ceiling.

## Aggressive step batching

`--batch` (or `/batch on`) enables a more aggressive orchestrator move that requires grammar support: after `update_tasks` emits N pending tasks that each name a file, the orchestrator runs `force_grammar_args("write_file", ...)` for each task and writes them all in one batch — no model round-trips between steps. Stops at the first ambiguity (no path inference, multi-file step, run_bash required). Each successful write flips the task to `completed`. Compounds with `--auto-screenshot` and `--auto-commit` for a "scaffold + render + commit" pipeline.

## Personas

Two layers, workspace wins:

1. `<workspace>/.loom/persona.md` — committed-with-the-project persona; loads automatically on session start and after `/cwd`.
2. `~/.loom/personas/<name>.md` + `--persona <name>` (or `LMSTUDIO_PERSONA` env) — shared personas across projects.

The persona text is prepended to the system prompt under `# Persona`. Use this to set tone, role, project conventions, or hard rules that aren't in `CLAUDE.md`.

## Cross-session permission learning

When you answer `a` ("yes, always this session") to a permission prompt, the choice is now persisted to `~/.loom/permissions/<sha256-of-workspace-path>.json` on session quit. Next time you start lmstudio in the same workspace, those grants restore automatically — `npm install` is allowed-forever per project, but never globally.

## LSP integration

`--lsp "typescript-language-server --stdio"` (or `/lsp <command>`) starts a stdio LSP server, runs the `initialize`/`initialized` handshake, and exposes three tools:

- `lsp_diagnostics(path)` — open the file in the LSP and wait briefly for `publishDiagnostics`. Returns errors/warnings/info/hints as `path:line:col [sev] message`.
- `lsp_definition(path, line, character)` — go-to-definition. Line/character are 0-indexed.
- `lsp_references(path, line, character)` — find references including the declaration.

Minimal client (no resources/prompts/sampling, one server at a time, no diagnostic refresh streaming). Pair with `typescript-language-server`, `pyright --stdio`, `sourcekit-lsp`, etc.

## find_todos

`find_todos(pattern?, path?)` greps the workspace for the usual markers (`TODO|FIXME|XXX|HACK|NOTE` by default) with `WORKSPACE_TREE_IGNORE` excluded so `node_modules` etc. don't dominate the results. Cap 200 hits.

## 8.0.0 — Claude Code parity batch

### Hooks system

Drop executable scripts into `~/.loom/hooks/<event>` or `<workspace>/.loom/hooks/<event>`. Workspace hooks run before user-level hooks. Events:

- `user-prompt-submit` — runs before each user message goes to the model. Stdin: `{"prompt", "workspace"}`. Non-zero exit blocks the prompt entirely. Stdout becomes a synthetic system note.
- `pre-tool-use` — runs before every tool dispatch. Stdin: `{"name", "args"}`. Non-zero exit refuses the call.
- `post-tool-use` — runs after every successful dispatch. Stdin: `{"name", "args", "result", "error": false}`. Stdout is appended to the tool result.
- `on-error` — runs after a tool raises. Stdin: `{"name", "args", "error"}`. Stdout is appended.
- `session-start` / `session-end` — one-shot bookends.

`/hooks` lists registered hooks; `/hooks reload` re-scans. Skip discovery entirely with `--no-hooks`.

### `ask_user` tool (interactive picker)

The model can call `ask_user(question, options[, header])` to present a multi-choice picker. Arrow keys navigate, Enter selects, Esc cancels. The picker always appends an "Other" option that lets the user supply free text. Returns JSON `{"selected", "index", "notes"}` back to the model. Non-TTY sessions fall back to a numbered prompt.

### `schedule_wakeup` + `loop_complete` + `--loop` mode

- `schedule_wakeup(delay_seconds, prompt, reason?)` writes a record to `~/.loom/wakeups/<id>.json` and returns. The agent does NOT block waiting — an external scheduler (cron / launchd) is expected to fire `lmstudio --check-wakeups` periodically.
- `lmstudio --check-wakeups` scans the wakeup directory and runs every record whose `wake_at` is in the past via `lmstudio --resume-wakeup <path>` as a fresh subprocess.
- `--loop` re-drives the same prompt in a tight loop until the model calls `loop_complete(summary)` (or hits the 100-iteration safety ceiling). Enables truly autonomous workflows.
- `/wake` lists pending wakeups.

### `.loom/settings.json`

Centralized workspace config. Loaded at session start; explicit CLI flags still win over settings.

```json
{
  "model": "qwen/qwen3-coder-30b",
  "theme": "cyberpunk",
  "allow_bash": true,
  "auto_test": true,
  "auto_compact": true,
  "auto_screenshot": false,
  "auto_commit": false,
  "aggressive_batching": false,
  "self_reflect": false,
  "max_continuations": 20,
  "router": {"planner": "qwen-3b", "coder": "qwen-30b"},
  "tools_disabled": ["http_request"],
  "env": {"OPENAI_API_KEY": "${KEYCHAIN:openai-key}"}
}
```

`${ENV:NAME}` interpolates env vars; `${KEYCHAIN:service}` runs `security find-generic-password -s service -w`. `/settings` shows the loaded config; `/settings reload` re-reads.

### Background bash trio

- `background_bash(command, label?)` — detaches a shell, returns a `shell_id`. Output streams to `~/.loom/shells/<id>.log`.
- `monitor(shell_id, follow?, until?, timeout?, lines?)` — read or follow the log. `follow=true` blocks for new output up to `timeout` seconds (default 30); `until` is a regex that ends the follow early.
- `bash_output(shell_id, since_line?, max_lines?)` — incremental reads.
- `kill_shell(shell_id)` — SIGTERM, escalate to SIGKILL after 5s.
- `/bg` lists, `/bg <command>` starts; `/mon <id>` reads; `/kill <id>` terminates.

### Jupyter notebook tools

- `notebook_read(path, cell_index?)` — read whole notebook or one cell.
- `notebook_edit(path, cell_index, new_source, run?)` — replace cell source; with `run=true`, execute via `jupyter nbconvert --execute --inplace`.
- `notebook_append(path, source, kind?)` — append a `code` or `markdown` cell.

Edits go through the journal so `/undo` rolls them back. `/nb <path>` shows the cell list.

### Worktree isolation for `spawn_agent`

Pass `isolation="worktree"` to `spawn_agent` and the subagent runs in `~/.loom/worktrees/<id>` (a temporary git worktree on a fresh branch). On exit the diff vs HEAD is printed; the worktree is preserved for inspection (clean up with `git worktree remove`). Parent workspace untouched even if the subagent thrashes.

### Slash command files

Drop a `.md` file into `~/.loom/commands/<name>.md` (user-level) or `<workspace>/.loom/commands/<name>.md` (workspace overrides user). The file's body becomes the prompt sent to the model when the user types `/<name>`.

Frontmatter (optional):

```markdown
---
description: Review the current changes for bugs
model: qwen/qwen3-coder-30b
---
Review the staged changes carefully. Look for:
- Bugs and logic errors
- Performance issues
- Test coverage gaps

$ARGS
```

`$ARGS` is replaced with whatever the user typed after the command name. `model` routes that single turn to a specific model.

### Skills (`~/.loom/skills/<name>/`)

A directory with `skill.md` (system-prompt addendum) and an optional `tools.py` (declaring `LMSTUDIO_TOOLS`) loads as a skill. `/skill <name>` activates it for the current session. `/skill` (no arg) lists installed skills with a `*` next to active ones. The model can also call `activate_skill(name)` mid-session.

Skills differ from plugins (always-on, persistent tools) by being session-scoped and prompt-extending — useful for "load my test-writing skill for the next 10 turns."

### Auto-memory (cross-workspace)

`~/.loom/memory/MEMORY.md` is a markdown index pointing at `~/.loom/memory/<name>.md` files. The contents are auto-injected into the system prompt regardless of workspace.

The model can call `save_memory(name, body, kind?)` to add a memory. `kind` is freeform (typical: `user`, `feedback`, `reference`). `/memory` prints the current MEMORY.md; `/memory reload` re-reads.

Workspace `project_knowledge` is for per-project state; user memory is for cross-workspace facts ("user prefers pytest", "user has a Loom project at ~/Documents/Xcode/Loom").

### Stability fixes (7.1.0 batch, shipped with 8.0.0)

- WebSocket frame buffering — added `_recv_exact` helper so frames no longer truncate on partial recv()s.
- Prefetch thread pool — bounded `ThreadPoolExecutor(max_workers=4)`; no more unbounded daemon spawn during heavy narration.
- Two-phase file watcher — 2s fast stat of the known set; 30s full rglob to discover new files. Cheap on huge repos.
- `run_bash` select-based reads — wakes every 1s to check the deadline; children that prompt without a newline are killed cleanly.
- Fail-fast missing args — when `_dispatch_tool` sees required args still missing after repair + grammar, it returns a structured error with the schema instead of letting the tool raise `KeyError`.
- Stale permission filter — `load_permission_grants` drops entries for tools no longer registered (e.g., uninstalled plugins).
- `ship_it` recursion fix — refactored to queue followups onto `state.queued_followups` and drain them after the human turn, avoiding the nested `run_turn` hazard.

## Internet access (7.0.0)

Five tools let the agent reach the web without going through the browser subprocess:

- `web_search(query)` — DuckDuckGo HTML scrape. No API key. Cap 20.
- `web_fetch(url, mode?)` — `mode='text'` (default) strips HTML, `'raw'` and `'html'` return as-is. Cap 64 KB. Honors `state.web_blocklist` (suffix match on hostname; `/blocklist <host>` to add).
- `http_request(method, url, headers?, body?)` — full REST. Permission-gated.
- `rss_fetch(url, limit?)` — stdlib `xml.etree`-based RSS/Atom parsing.
- `websocket_subscribe(url, message?, until?)` — RFC6455 client implemented over `socket`. Connects, optionally sends one frame, collects frames until `until` regex matches or 30s. Permission-gated.

## GitHub workflow (7.0.0)

Six tools wrap the `gh` CLI: `gh_create_pr`, `gh_pr_view`, `gh_pr_comment`, `gh_issue_list`, `gh_issue_create`, `gh_issue_view`. PR creation is permission-gated and drafts by default.

## Databases (7.0.0)

`sqlite_query` runs through stdlib `sqlite3` — fully local, no extra deps. `postgres_query`, `mysql_query`, and `redis_query` shell out to `psql`, `mysql`, and `redis-cli`. All queries that match the mutation regex (`INSERT|UPDATE|DELETE|DROP|TRUNCATE|ALTER|CREATE|REPLACE`) are refused unless `allow_mutation=true` is passed explicitly.

## macOS-native (7.0.0)

- `keychain_get(service, account?)` — `security find-generic-password -w`. Returns the raw password so the agent can use it (e.g., as a Bearer token for `http_request`).
- `mdfind(query, path?)` — Spotlight metadata search via `mdfind`.
- `notes_create(title, body)`, `notes_search(query)` — Apple Notes via `osascript`.
- `calendar_today()`, `calendar_create(title, when, duration?)` — Apple Calendar via `osascript`.
- `screen_capture_region()` — `screencapture -i` with interactive selection; returns the saved PNG path.

## Symbol intelligence (7.0.0)

`symbol_search(query, kind?)` indexes the workspace's symbols. Uses `universal-ctags` when available; otherwise falls back to a regex scan covering `.py / .js / .ts / .tsx / .jsx / .swift / .go / .rs`. Index is cached on first use; subsequent calls are instant.

`package_list()` reads the appropriate manifest (`package.json`, `requirements.txt`, `pyproject.toml`, `Cargo.toml`, `go.mod`, `Brewfile`). `package_install(name, version?, manager?)` shells out to the obvious package manager. Auto-detect uses the same manifest hits. Permission-gated.

## Sandboxed code execution (7.0.0)

`exec_python(code, timeout?)` runs a snippet through `python3 -I -S -c` (no site-packages, isolated env) inside a fresh `/tmp` directory. `exec_js(code, timeout?)` does the equivalent with `node -e`. Both default to a 10s wall-clock cap, max 60s.

Use for testing one-off snippets without mutating the workspace.

## Continuous file watcher

`--watch` (or `/watch on`) starts a 2-second polling watcher over the workspace tree. External file additions / changes / deletions are collected into a buffer; the buffer is flushed as a system message at the start of the next turn so the model knows to re-read files you've edited yourself. Stop with `/watch off` or session quit.

## Cost meter (per-tool)

`/cost` now shows a per-tool breakdown: calls, elapsed ms, estimated tokens. Plus a "top file paths read" list so you can see what the model fixated on. Prefetch hits/misses are also shown.

## Plugin architecture

Drop a Python file into `~/.loom/tools/` that defines `LMSTUDIO_TOOLS = [{"schema": ..., "func": ...}]` and lmstudio will auto-import it on session start. Each entry registers a new builtin tool. Errors during import surface as warnings but never abort the session. Use `/plugins` to list loaded plugins. Disable with `--no-plugins`.

Example plugin:
```python
# ~/.loom/tools/weather.py
def tool_weather(state, args):
    return f"It's always sunny in {args['city']}"

LMSTUDIO_TOOLS = [{
    "schema": {"type": "function", "function": {"name": "weather",
        "description": "Get the weather.",
        "parameters": {"type": "object", "properties": {
            "city": {"type": "string"}}, "required": ["city"]}}},
    "func": tool_weather,
}]
```

## Self-reflection + drift

`--reflect` (or `/reflect on`) sends a small judge prompt at the end of each human turn that scores the turn and writes a one-line lesson into `.loom/project.json` under `lessons`. Future sessions read those lessons through the project knowledge load.

Drift detector runs at session start: any `build_commands` recorded in project knowledge that reference files no longer in the workspace get flagged in the banner. Prevents stale knowledge from poisoning sessions.

## Mermaid rendering

When the assistant turn contains a ` ```mermaid` block, lmstudio pipes it through `mmdc` (Mermaid CLI, `npm i -g @mermaid-js/mermaid-cli`) and writes the PNG to `diagrams/mermaid-<ts>.png`. Silent skip when `mmdc` isn't on PATH.

## Constitution mode

Drop a `<workspace>/.loom/constitution.md` with hard rules — one per line — and lmstudio injects it into the system prompt AND validates every tool call against it before dispatch. If the model tries to violate a rule, the dispatcher refuses *before* the tool runs and tells the model exactly which rule it broke.

Rules can be:
- **Mechanical** (matched by built-in patterns): `rm -rf`, `git push --force`, `DROP DATABASE`, `DROP TABLE`, `TRUNCATE TABLE`.
- **Phrase-based**: if a rule mentions a tool name plus a forbidden phrase in backticks/quotes, the dispatcher will refuse matching args.

Example `.loom/constitution.md`:
```markdown
# Constitution

- Never call `run_bash` with `rm -rf`.
- Never call `run_bash` with `git push --force`.
- Never call `sqlite_query` with `DROP TABLE`.
- Refuse `http_request` to any host under `production.example.com`.
```

`/constitution reload` re-reads the file mid-session. `/constitution` (no args) lists the active rules.

## ship_it

`ship_it(spec, target?)` is the end-to-end capstone. One tool call:

1. Runs an aggressive-batch turn against the spec (model emits tasks → orchestrator scaffolds files in one batch via grammar-forced writes).
2. Runs the workspace's test runner (`detect_test_runner`).
3. Auto-commits the journaled changes.
4. Opens a draft PR via `gh_create_pr`.
5. Notes a deploy target if one was provided (but does NOT execute it; manual step).

Permission-gated. Use `/ship "<spec>"` to invoke from the REPL.

## Slash commands added in 7.0.0

`/watch [on|off]`, `/reflect [on|off]`, `/plugins`, `/constitution [reload]`, `/ship <spec>`, `/web <query>`, `/blocklist [host|-host]`.

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

## 8.0.3 fixes

- `update_tasks({})` (empty call) no longer silently clears the visible task list. The dispatcher refuses the call, returns a schema-aware error, and preserves the existing tasks. This was the root cause of the 8.0.x "model loops forever narrating without writing files" pattern.
- Zero-progress orchestrator guard. The continuation loop tracks consecutive turns where no real tool work happened (only narration + bare `update_tasks` calls) and breaks out after 2 unproductive rounds, returning control to the user instead of running through the full 12 continuations.
- Up/down arrow history fixed. Three causes were in play simultaneously: the Esc-to-CSI peek timeout (40 ms) was too tight for some terminals, VMIN/VTIME were never set in the manual termios setup so `read(1)` could return early with no bytes, and `\x1bOA`-style SS3 application-cursor-key sequences weren't handled. All three are addressed.

## 8.0.19 — dual-load + per-turn routing (Claude-style)

The user asked: "Why can't I use a low-end model, then have it switch mid-generation to a better one for tool calls?" 8.0.19 does the next best thing — loads two models simultaneously and routes each turn to the appropriate one.

How it works:

1. **At session start, dual-load both a planner and a coder.** `auto_load_dual_models` picks the best small fast model (default ~4B, jan-v1-4b on the test system) AND the best stronger coder-class (default ~9B, qwen/qwen3.5-9b). Both loaded with `--parallel 1` to keep memory usage minimal.

2. **Per-turn routing in `pick_model_for_turn`.** The router scans the user message for intent:
   - **Coder words** (write, create, build, scaffold, implement, fix, refactor, code, generate, function, class, module, etc.) → `coder_model`.
   - **Explainer words** (explain, why, how does, summarize, describe) → `explainer_model` (falls back to planner).
   - **Planner words** (plan, outline, design, what should we) → `planner_model`.
   - **Default**: coder when set, else `state.model`.

3. **Streaming completion stays on the picked model** for the duration of the turn. We don't (yet) swap mid-stream — that's a much harder problem because the inference state lives inside the model. Per-turn is the practical middle ground and covers 90% of the real win.

Memory cost on the test system: 4B + 9B GGUFs at Q4 plus runtime = ~9 GB total. Easily fits alongside the model weights of either alone (~33 GB previously for the 31B Gemma).

OOM fallback: if the second load OOMs, the agent continues with just the coder; the routing slots stay empty and `pick_model_for_turn` falls through to `state.model`. The banner shows `family qwen3 (native tools)` instead of dual.

Flags:

- `--dual-load` (default on, `LMSTUDIO_DUAL_LOAD=0` to disable).
- `--no-dual-load` shorthand.
- `--planner-size N` (default 4).
- `--coder-size N` (default 9).

About mid-stream model swap. Real Claude-style "switch model mid-generation" requires re-prompting the new model with the same conversation when a tool call header appears. That's a bigger feature (would need explicit stream-cancel + handoff prompt + KV state transfer). Per-turn routing covers the bulk of the perceived benefit. Open a follow-up if you want true mid-stream swap.

## 8.0.18 — fix the actual reason the update pill never showed

Root cause from the user's running app log:

```
Update check failed: Error Domain=NSURLErrorDomain Code=-1001
"The request timed out."
URL: https://api.github.com/repos/BigBeardedMan/Loom/releases?per_page=30
```

The 10-second timeout on the GitHub API request was too tight for the user's network. Every poll cycle timed out, so the manifest never got written, so `refresh()` never set `available`, so the pill never appeared.

Three layered fixes:

1. **Bump every URLRequest timeout from 10s → 30s** in `GitHubReleaseFetcher` (releases list, latest, checksum sidecar). Slow networks, DNS lag, and busy laptops were all paying the price for a budget tuned to a fast desktop.

2. **Add a one-shot retry on transient errors** in `UpdateService.checkRemote`. URLError codes `-1001` (timed out), `-1009` (not connected), `-1004` (cannot connect), `-1005` (network connection lost) get a 3-second backoff and one more attempt before reporting failure. Drops the cost of an unlucky moment from "wait 60s for the next poll" to "wait 3s and retry inline."

3. **Diagnosed in passing**: the user's `/Applications/Loom Testing Edition.app` doesn't exist — they were running directly from the staging directory. The apply script swaps the staged bundle INTO `installedBundleURL`, which is hard-coded to `/Applications/Loom Testing Edition.app`. Without a real install there, no manifest gets cleared after apply, no clean handoff. **Manual one-time step:** download `LoomTestingEdition-8.0.18.dmg` from the GitHub release, drag the app into `/Applications`, launch from there. After that, the pill mechanism works.

## 8.0.17 — session-start auto-route (force the upgrade)

8.0.16 fixed the auto-load picker but auto-load only fires when nothing is loaded. A user with a 4B model already loaded from a prior session stayed on that model forever, even when their qwen3.5-9b was sitting on disk unused.

8.0.17 makes auto-route actually swap. At session start:

1. Read the currently-loaded models from `/api/v0/models`.
2. Compute the optimal pick from disk via `pick_default_model` (coder-family bias, prefer 7B, cap 12B).
3. If a model is loaded but the optimal pick differs, unload the loaded one and load the optimal via `lms load ... --parallel 1 -c 16384`.

Side effects:

- Explicit `--model X` skips the swap entirely.
- `--no-auto-route` (or `LMSTUDIO_NO_AUTO_ROUTE=1`) skips the swap and uses whatever's loaded.
- Multiple models loaded: pick the optimal one of them.

Dry-run on the test system: `jan-v1-4b` loaded → optimal pick `qwen/qwen3.5-9b` → swap planned. After install, every session with auto-route on will move the user onto a coder-class model when one is available, no manual `lms load` required.

The swap costs ~10 seconds (unload + reload). Trade-off: one-time tax for a measurably stronger model for the rest of the session. Use `--no-auto-route` if you want the launch to be instant.

## 8.0.16 — coder-aware default + faster update pill

Two real fixes from the field.

**Default model now biases toward coder-strong families.** 8.0.13's auto-load picked the smallest 4B-class model regardless of whether it was meant for code. On a user system with both `jan-v1-4b` (generalist 4B) and `qwen/qwen3.5-9b` available, the picker would auto-load the 4B and then struggle on coding tasks like "scaffold a website."

New scoring in `pick_default_model`:
1. **Coder family score** (primary). Regex over key + architecture: `qwen`, `deepseek`, `codestral`, `coder`, `stable-code`, `yi-coder`, `magicoder`, `wizardcoder`, `starcoder`, `granite-code`, `codellama`, `codegemma`. Matches score 0; everything else scores 1.
2. **Distance from `--default-size`** (now 7, was 4).
3. **File size on disk** (smaller wins ties between same-family same-size).
4. **Alphabetical key** for determinism.

Hard cap raised from `--default-size-max=8` to `12` so 9B qwen variants are eligible. On the test system this flips the auto-pick from `jan-v1-4b` → `qwen/qwen3.5-9b` — exactly what a coding session wants.

**Update pill checks on app activation.** Previously only every 60 seconds via the background poll. 8.0.16 adds an `onReceive(NSApplication.didBecomeActiveNotification)` hook in `LoomApp` so coming back to Loom from another app triggers an immediate `checkRemote()`. The 60-second background poll still runs as a safety net.

## 8.0.15 — fix mouse-click random-char injection

Clicking inside the input box was inserting characters like `0;42;15` into the in-flight line. Cause: when a terminal has SGR mouse tracking enabled (vim or tmux often leave it on for the parent shell), a click emits `\x1b[<0;42;15M`. The editor's CSI handler only recognized digit-prefixed multi-byte sequences, so the `<` parameter prefix fell through to `_handle_csi("<")` (a no-op) and the trailing `0;42;15M` bytes were read as individual printable characters and inserted into the line.

Two fixes layered:

1. **Drain any CSI sequence that isn't one of the known single-byte commands** (A/B/C/D/H/F/Z). Anything else is multi-byte and gets consumed until its terminator (`~` or any alpha). Covers SGR mouse press/release (M / m), DEC private mode replies, function keys, and any other CSI sequence the terminal might send.

2. **Explicitly disable all mouse tracking modes** at session start: `\x1b[?1000l\x1b[?1002l\x1b[?1003l\x1b[?1006l\x1b[?1015l`. Belt + suspenders so the terminal stops sending mouse events altogether even if a parent program (vim, tmux) left them on.

Note: with this fix, mouse clicks are silently consumed rather than corrupting input. Click-to-position-cursor inside the input is a separate feature (would require enabling SGR mouse, parsing click coordinates, mapping them to a char offset in the wrapped line) — currently not implemented; cursor positioning is via arrow keys, Home/End, Ctrl-A/E.

## 8.0.14 — friendly install detection

If someone runs `lmstudio` without LM Studio installed at all, the CLI now detects that and points them to the download page instead of erroring out with a Python URLError.

Three distinguishable failure modes at startup, each with its own message:

1. **Not installed.** No `lms` CLI on PATH, no `~/.lmstudio` directory, no `LM Studio.app` in /Applications. Prints "LM Studio does not appear to be installed on this Mac" with the download URL and a one-line walkthrough: install → open app → Discover tab → download a 4B model → re-run `lmstudio` (auto-load picks it up on first launch).

2. **Installed but server cold.** App markers found, but no response from `/v1/models`. Prints "LM Studio is installed but the local server isn't reachable" with two ways to start it: open the app and click Developer → Local Server → Start, or run `lms server start` from the shell.

3. **Reachable.** Normal session flow continues.

Detection is a fast pre-flight: 2-second timeout on `/v1/models`, plus filesystem checks for `~/.lmstudio`, `/Applications/LM Studio.app`, and `~/Applications/LM Studio.app`. Runs before any other model probing so the first thing a brand-new user sees is the friendly nudge, not a stack trace.

## 8.0.13 — zero-config model selection

Until 8.0.13, launching the CLI with no model loaded in LM Studio errored out and demanded the user load one manually. Now the CLI inspects `lms ls --json`, picks the best small tool-use model on disk, and loads it automatically.

How the default is chosen:

1. Enumerate all LLMs on disk via `lms ls --json`. Filter to local (`deviceIdentifier=null`) + tool-use trained (`trainedForToolUse=true`).
2. Score each candidate by `(distance from --default-size, file size on disk, name)`. Default `--default-size=4` so 3-4 B models win. Hard cap `--default-size-max=8` skips anything larger.
3. Tie-break by actual disk size, so a 4B dense model beats a 26B-A4B MoE that just happens to share active-params count.
4. Load via `lms load <key> -y --parallel 1 -c 16384 --gpu max`.

Live-tested against a system with seven local tool-use LLMs (3B to 31B): picked `jan-v1-4b` (2.5 GB, qwen3 arch, tool-use). Loaded in under 10 seconds.

Manual override flags:

- `--no-autoload` keeps the old "error out" behavior.
- `--default-size N` picks closer to N billion params.
- `--default-size-max N` raises or lowers the hard cap.

In-session model management:

- `/models` lists every local LLM with size, context cap, tool-use status, loaded marker.
- `/load <key> [ctx]` loads a model (auto-rebuilds the family adapter + essential-tools flag for the new model).
- `/unload <key>` unloads.

## 8.0.12 — multi-task transcript economy

Targets the "slow after 3-4 tasks" pattern by reducing per-turn token waste. The agent's API calls send the entire transcript on every turn; older messages keep paying tokens forever. This release adds four mechanisms that keep the working set small.

1. **Stale tool-result pruning.** At the top of every turn, walk the transcript and replace older tool result bodies with a 240-char head plus a "[pruned: full result was N chars, re-call to fetch]" marker. Keeps the most recent six tool results full. A session that read a 500-line file 5 turns ago stops paying 2k+ tokens for it on every subsequent API call. The model can re-call any tool if it needs the rest.

2. **`read_file` truncation at source.** Files longer than 1500 lines now return the first 100 + last 50 lines with a `[TRUNCATED ... use offset/limit for range]` marker. The new `offset` (1-indexed start line) and `limit` (line count) arguments let the model fetch any specific range instead of dragging the whole file into context. Schema advertises the new parameters so models discover them naturally.

3. **Cached grammar probe.** The session-startup grammar capability probe is now cached to `~/.loom/cache/grammar/<key>.json` with a 7-day TTL. Subsequent sessions with the same model skip the 5-10 second live probe. Force a re-probe by deleting the cache file or setting `LMSTUDIO_NO_GRAMMAR=1`.

4. **Lower auto-compact threshold.** `COMPACT_TRIGGER_RATIO` dropped from 0.75 to 0.60. Compaction kicks in earlier, leaving more usable headroom on the back half of long sessions before the model starts losing context.

These compose with the existing 8.0.9 `cache_prompt: true` to give the agent a much smaller working set across turns. The stable prefix (system prompt + tool catalogue) stays cached, the dynamic tail (recent tool results + assistant messages) stays the only thing actively burning compute.

## 8.0.11 — Shift+Tab mode cycle (4 modes, Claude Code parity)

Updated to four modes matching Claude Code exactly. Press Shift+Tab to cycle:

- **default** — permissions gate everything. Normal behavior.
- **PLAN** — read-only. Hard-blocks write_file / edit_file / multi_edit / run_bash / background_bash / git_commit / ship_it / spawn_agent at the dispatcher level. Allowed: read tools, list/glob/grep, git read-only, update_tasks, recall.
- **ACCEPT EDITS** — write_file, edit_file, multi_edit auto-approve without prompts. run_bash still gates. Useful when you trust file edits but want to review shell commands.
- **BYPASS PERMISSIONS** — full yolo. All permission prompts off; bash auto-enabled; every tool runs without confirmation. Use when you trust the model end-to-end.

The active mode renders as a colored pill in the input box's top border: `╭── [ACCEPT EDITS] ──────╮`. Default mode shows no pill (clean look).

CLI flag `--bypass-bash` (alias `--bypass-permissions`) launches directly into BYPASS PERMISSIONS mode. Equivalent to launching then pressing Shift+Tab three times. `LMSTUDIO_BYPASS_BASH=1` env var also works.

Side effects per transition are computed from a clean baseline each time — switching back to default reliably restores `permissions.yolo` to its launch-time value and clears the `allowed_forever` set, so a session that briefly used BYPASS PERMISSIONS doesn't leak yolo state into a return to default mode.

On every mode change, a synthetic system note is appended to the transcript so the model knows about the switch on the next turn. The dispatcher hard-block still catches plan-mode violations as the final safety net.

`/mode <name>` switches by name for terminals that swallow Shift+Tab. Names: `default`, `plan`, `accept-edits`, `bypass-permissions`.

## 8.0.9 — multi-task performance

Five additions targeting wall-clock latency on multi-tool workflows. None of them help GPU throughput, but together they shave a lot of waste off each round-trip.

1. `cache_prompt: true` on every completion call. LM Studio / llama.cpp reuses the KV state for unchanged prefixes across turns. System prompt + tool catalogue stay identical turn-over-turn, so the second turn onward only pays for the new user message and assistant output. Time-to-first-token on follow-up turns drops 60-80% in practice.

2. Per-turn output token cap. `--max-tokens` (default 4096) prevents runaway narration like Gemma's "Step 1: Setup. Step 2: Initialize. Step 3: ..." essays that burned 60 seconds before reaching a tool call. The cap fits one tool call plus reasonable preface; raise via `--max-tokens N` or `LMSTUDIO_MAX_TOKENS` env.

3. Early-stop streaming after a fenced `\`\`\`tool_call` closes. For text-mode families only. The moment the model writes the closing ``` we cut the stream rather than waiting for whatever filler prose follows. Combined with #2 this often cuts a turn's wall-clock by 30-50%.

4. Workspace tree dump trimmed from 200 → 80 entries. The tree is auto-injected into every system message, so each entry is paid for in every turn forever. 80 is enough for the model to orient; the prior 200 was bloating cache size and slowing first-token on flat projects.

5. Auto multi-model routing. When the user has multiple models loaded in LM Studio, lmstudio picks the smallest (by parameter count parsed from the model id) and assigns it as `planner_model`. Triage / planning prompts route there, the user's `--model` stays the coder. Explicit `--planner-model`, `--coder-model`, `--explainer-model` flags override.

## 8.0.8 — auto-scale that actually scales

8.0.7 detected the small context but failed to bump it on memory-constrained systems. Live-testing on a 36 GB Mac with Gemma 4 31B revealed why: LM Studio's JIT load defaults to `parallel=4`, which keeps four KV cache slots in memory simultaneously. Most agent workloads run one completion at a time, so three of those slots are pure waste.

8.0.8 changes the autoscale strategy:

- Always force `--parallel 1` on the reload. That alone shrinks the KV cache by 75% per token.
- Always `lms unload <id>` before the load, so the new instance reclaims the original identifier instead of being assigned `:2` / `:3` / etc.
- Initial target raised to `min(--autoscale-max, model_cap)` rather than `loaded * 4`. With parallel=1 the bigger sizes actually fit.
- Default `--autoscale-min` raised to 16384 and `--autoscale-max` to 65536.

Verified on the same hardware that previously refused any bump: Gemma 4 31B (Q4_K_M) now loads at 65536 context, parallel=1, using the same 33.84 GB unified memory that 4096 context previously required. The trick is that llama.cpp on Apple Silicon mmaps the model weights, so weights page in on demand and the in-memory delta is only the actively-used KV cache.

Also: when a non-OOM error happens mid-ladder, autoscale tries to restore the prior loaded size before returning so the user isn't left with no model loaded.

## 8.0.7 — auto-scale model context at session start

LM Studio's JIT loader gives many models a tiny default `loaded_context_length` (often just 4096) even when the model's GGUF supports 32k, 128k, or 262k. The lmstudio CLI now bumps this automatically.

How it works:

1. At session start, query `/api/v0/models` for the loaded model's `loaded_context_length` and `max_context_length`.
2. If `loaded_context_length < --autoscale-min` (default 8192) AND the cap allows more, build a candidate ladder: `min(autoscale-max, cap, loaded * 4)` at 100% / 75% / 50% / 33% / 25%.
3. For each candidate (highest first), shell out to `lms load <model> -c <target> -y --gpu max`. On a non-OOM error, abort. On an OOM error ("insufficient system resources", "out of memory", "would likely overload"), step down to the next candidate.
4. Stop at the first successful load. Update the status footer with the new size.

Hard cases handled cleanly:

- Very large models on tight RAM (e.g. Gemma 4 31B on 36 GB) - the ladder exhausts, the agent logs a clear warning, and starts the session on the smaller context. Tool surface auto-trims to the essentials.
- `lms` not on PATH - falls back to `~/.lmstudio/bin/lms`. If neither exists, skips autoscale with a one-line note.
- Server cold - autoscale fails silently and the agent reports the underlying connection error on the next call.

Manual control:

- `--no-autoscale` skips at session start.
- `--autoscale-min N` raises or lowers the threshold (LMSTUDIO_AUTOSCALE_MIN env var).
- `--autoscale-max N` caps the ladder's top candidate.
- `/autoscale <target>` mid-session to bump again. `/autoscale max` targets the model's cap. `/autoscale` with no argument shows current loaded/cap values.

Also: `fetch_model_context_window` now reads `loaded_context_length` (the runtime capacity) rather than `max_context_length` (the GGUF cap). The status footer no longer shows misleading "262k context" for a model actually loaded with 4k.

## 8.0.6 — text-mode tool calling actually works on Gemma

The 8.0.5 framework was correct in shape but the model still wouldn't tool-call from a prose-heavy plan. 8.0.6 adds three reinforcements so Gemma (and other text-mode families) reliably emit JSON tool calls instead of writing essays:

1. **TEXT_TOOL_INSTRUCTIONS rewritten and prepended.** The format guidance is now the FIRST thing the model sees, not the last. Includes a complete worked example and an explicit anti-pattern list: no multi-step prose plans, no "Commands to Execute" markdown headings, no descriptions of what the tool will do. Just the fenced `\`\`\`tool_call` block.

2. **Plan-without-action detection in `should_auto_continue`.** When a non-native family emits a long response (>200 chars) containing file paths or shell-command tokens but no tool calls, the orchestrator injects a strict "emit ONE tool call NOW" nudge instead of giving up.

3. **Grammar-forced rescue.** Last resort: when the zero-progress streak hits the limit on a text-mode family, the orchestrator picks the most likely intended tool from the model's narration (`write_file` if paths are present, `run_bash` if backticked commands are mentioned, etc.), forces valid arguments via `response_format` JSON schema, dispatches the result, and appends a synthetic system note. The loop continues from the rescued state. Capped at 2 rescues per human-issued turn to prevent runaway.

The fix flow for a typical "build me a website" prompt under Gemma:

- Turn 1: model writes a plan as prose. Extractor finds nothing. Plan-without-action detector fires.
- Turn 2: model retries; emits a proper `\`\`\`tool_call` block this time. Extractor parses it. Dispatch runs.
- If turn 2 still fails: zero-progress streak fires. Grammar-rescue infers `write_file`, forces args, dispatches.
- Turn 3+: model sees the rescued state and continues normally.

## 8.0.5 — model family adapters

`bin/lmstudio` now ships a `ModelAdapter` layer that recognizes the family of the loaded model and adjusts behavior accordingly. The agent works on Qwen3, Qwen2.5-Coder, Gemma 2 / Gemma 3, Llama 3.x, Llama 2, DeepSeek-Coder, DeepSeek-R1, Codestral, Mistral, Phi-3 / 3.5 / 4, Granite, Hermes, and Yi-Coder out of the box. Unknown model ids default to "try native tools, fall through to text extraction" so an unfamiliar checkpoint still does useful work.

Behavior changes per family:

- **Native tool callers** (Qwen3, Qwen-Coder, Llama 3.x, DeepSeek, Codestral, Mistral, Phi-3.5/4, Hermes): the dispatcher trusts the structured `tool_calls` field and acts on it directly.
- **Text-mode families** (Gemma, Llama 2, base Phi-3): a TEXT_TOOL_INSTRUCTIONS block is appended to the system prompt explaining the JSON-in-text wire format. After streaming, the agent scans the assistant text for any of these wire forms and re-dispatches them as tool calls.

Wire formats accepted by the text extractor:

```
<tool_call>{"name": "...", "arguments": {...}}</tool_call>
<function_call>{...}</function_call>

```tool_call
{"name": "...", "arguments": {...}}
```

```json
{"tool_calls": [{"name": "...", "arguments": {...}}, ...]}
```

```json
{"name": "...", "arguments": {...}}
```

Plus a trailing bare-JSON object at the end of the message as a last-resort fallback. Unknown tool names are rejected by the extractor so prose mentions of "name": don't accidentally fire calls.

Per-family essentials default. Small / less-reliable families (Gemma, Phi-3, Llama 2, Granite) default to the 15-tool essentials subset so the runtime schema fits the native context window. Full 70+ surface is one `/tools full` away.

New slash commands:

- `/model-info` — print what the adapter detected, capabilities, and current essentials/full setting.
- `/tools [full|essentials]` — toggle or set the tool surface manually.
- `/model <id>` now rebuilds the adapter and re-applies the new family's defaults.

The banner shows `family <name> (native tools | text-mode tools)` so you know what you're talking to before the first prompt.

## 8.0.4 fixes

- Progress snapshot order. In 8.0.3 the new-completions snapshot was taken AFTER `verify_task_completions` mutated `raw_tasks` in place, so a legitimate completion that got false-flipped by the verifier was counted as zero progress. The snapshot now happens before the verify call, and progress is only credited when verify reports no failures.
- Duplicate subjects in the task list no longer collide in the progress check. Switched from `set` to `collections.Counter` so two tasks with the same subject string register as two distinct completions.
- Partial escape sequences from slow terminals no longer wipe the input line. When `Esc + [` or `Esc + O` arrived but the trailing byte missed the 120 ms window, the editor previously assumed the user pressed plain Esc twice and cleared the buffer. It now drops the partial sequence and resumes editing.
