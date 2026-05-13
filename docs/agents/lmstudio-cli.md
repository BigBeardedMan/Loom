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
| `/cwd [path]` | Show or change the workspace root (reloads project context) |
| `/cost` | Approximate token count, elapsed wall-clock, tok/s |
| `/tasks` | Re-render the current task list |
| `/save [name]` | Save the session to `~/.loom/sessions/<name>.json` |
| `/resume [name]` | Load a saved session (most recent if no name) |
| `/sessions` | List saved sessions |
| `/system <text>` | Override the system prompt and reset the transcript |
| `/sh <cmd>` | Run a shell command yourself (no agent involved) |
| `/yolo [on\|off]` | Toggle permission prompts off (use with care) |
| `/theme <name>` | Switch palette (default, mono, cyberpunk, solarized) |
| `/quit`, `/exit` | Leave the REPL |

## @file mentions + tab completion

Type `@path/to/file` in your message to inline that file's contents:

```
❯ refactor @src/parser.py to use pathlib
```

The CLI rewrites the prompt to include a tagged `<file path="...">…</file>` block before sending. Tab completes paths from the workspace; for slash commands it completes the command name.

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

## Task tracking

Every `update_tasks` call writes one JSON file per task to `~/.loom/tasks/<session-id>/<task-id>.json` in Claude's shape. `LiveAgentTasksService` polls that directory every 2 seconds and surfaces sessions under the **lmstudio** source in Loom's Tasks pane.

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
