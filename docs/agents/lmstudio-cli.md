# `lmstudio` CLI

A terminal agent that talks to your local LM Studio server. Same shape as
`claude` or `codex`: type the command, get an interactive agent with
read/write/edit/list/bash tools and a visible task list. The task list lands
in Loom's Tasks pane automatically — same as Claude Code sessions do.

## Install

From inside this repo:

```bash
bin/install-lmstudio.sh
```

That symlinks `bin/lmstudio` to `~/.local/bin/lmstudio`. The script prints
a `PATH` hint if `~/.local/bin` isn't already on it. No sudo. No `pip
install` — the CLI is stdlib-only Python.

## One-time setup

1. Start LM Studio's local server: **LM Studio → Developer → Local Server → Start** (default port `1234`).
2. Note the model identifier shown in the active session, e.g. `qwen2.5-coder-7b-instruct`.
3. Export it (or pass `--model` every time):

   ```bash
   export LMSTUDIO_MODEL=qwen2.5-coder-7b-instruct
   ```

## Usage

```bash
lmstudio                           # interactive REPL
lmstudio "refactor the parser"     # one-shot
lmstudio --allow-bash "fix the failing test"
lmstudio --base-url http://lan-host:1234/v1 --model some-model
```

The CLI runs in the current working directory. All tool paths are
resolved relative to it, and the runner refuses to read or write outside
that directory.

### Flags

| Flag | Default | Notes |
| ---- | ------- | ----- |
| `--base-url` | `http://localhost:1234/v1` | OpenAI-compatible endpoint. Env: `LMSTUDIO_BASE_URL`. |
| `--model` | — (required) | Model identifier exposed by LM Studio. Env: `LMSTUDIO_MODEL`. |
| `--workspace` | `$PWD` | Root directory the tools may touch. |
| `--allow-bash` | off | Enables `run_bash`. Off by default — local models running bash without supervision is a foot-gun. Env: `LMSTUDIO_BASH=1`. |
| `--max-turns` | 30 | Hard stop for the agent loop. |

### REPL commands

- `/quit` or `/exit` — leave the REPL (Ctrl-D also works).
- Anything else is sent to the agent as a new user turn. The transcript
  is kept in memory for the duration of the session.

## Tools

Same toolset as Loom's in-app agent pane:

- `read_file(path)` — read a UTF-8 file (capped at 32 000 chars)
- `write_file(path, content)` — create or overwrite a file
- `edit_file(path, old_string, new_string)` — exact-substring replace
- `list_dir(path)` — directory listing
- `run_bash(command, timeout_seconds?)` — shell, gated behind `--allow-bash`
- `update_tasks(tasks)` — replace the visible task list

## Task tracking

Every `update_tasks` call writes one JSON file per task to:

```
~/.loom/tasks/<session-id>/<task-id>.json
```

The schema matches Claude Code's `~/.claude/tasks/` layout, so Loom's
`LiveAgentTasksService` picks them up under the **lmstudio** source on its
2-second poll. In the Loom Tasks pane you'll see a **Live · &lt;session&gt;**
block with a `cpu` icon (purple) for each running `lmstudio` session.

When the agent answers in plain text (no tool calls), the loop ends and
any leftover `pending` / `in_progress` tasks are flipped to `completed`.

## Model recommendations

The tool-calling pattern collapses fast on small or non-coder models.
Reliable picks running through LM Studio:

- Qwen2.5-Coder 7B Instruct (smallest model that holds tool-calling tightly)
- Qwen2.5-Coder 14B Instruct
- DeepSeek-Coder-V2-Lite-Instruct
- Llama 3.1 70B Instruct (if you have the VRAM)

General-purpose 3B–4B models will usually skip `update_tasks` or call it
once and forget. Stick to coder-tuned families.

## Troubleshooting

**"Could not reach LM Studio at http://localhost:1234/v1"** — server isn't
running. **Developer → Local Server → Start** in the LM Studio app, or
`lms server start --port 1234` if you have the LM Studio CLI installed.

**"--model is required"** — set `LMSTUDIO_MODEL` or pass `--model`. The
LM Studio server doesn't expose a default model identifier the way
OpenAI's API does.

**Model returns plain text without calling tools** — the model isn't
following the system prompt. Try a larger or more code-tuned model, or
phrase the request to make the next action obvious (e.g. "first read
`src/parser.py` then propose changes").

**Tasks aren't appearing in the Loom Tasks pane** — confirm Loom is
running and the **Stale window** in Settings → Tasks isn't set so tight
that the session is being hidden. Check `~/.loom/tasks/&lt;session&gt;/` —
if files exist there, the pickup is on Loom's side.
