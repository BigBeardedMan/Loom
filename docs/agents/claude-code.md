# Claude Code

Loom's default agent. Drives the [Claude Code CLI](https://docs.claude.com/en/docs/agents-and-tools/claude-code/overview) as a subprocess so the chat surface uses your existing OAuth login — no API key required.

## Requirements

- `claude` on `PATH` (install via `npm i -g @anthropic-ai/claude-code` or the official installer).
- An authenticated Claude Code session (`claude auth login` if you haven't already).

If `claude` isn't on `PATH` Loom will surface the error in the message banner — the subprocess just fails to launch.

## How it works

Each Agent pane creates one `ClaudeCodeProvider` instance with a stable session UUID. The first send runs:

```bash
claude -p --session-id <uuid> '<your prompt>'
```

Subsequent sends use `--resume <uuid>` so context carries forward across turns. The session id (first 8 chars) is shown in the header next to the provider label.

## Sub-agent picker

The picker queries `claude agents list` and surfaces every plugin and built-in sub-agent. Picking one passes its name as `--agent <name>`:

```bash
claude -p --agent feature-dev:code-architect --resume <uuid> '<your prompt>'
```

Refresh the list (the ↻ icon) after installing a new plugin or editing your `~/.claude/agents/` definitions.

## Cancelation

The stop button calls `Process.terminate()` on the active subprocess. The CLI handles SIGTERM cleanly — the next turn resumes the same session.

## Working directory

The Agent pane passes the workspace's folder URL as the subprocess `cwd`, so `claude`'s tool calls target the right project. Set the workspace folder before sending the first prompt; switching folders mid-session does not migrate context.

## Streaming caveat

The Claude Code provider waits for the subprocess to exit before populating the bubble — there's no token-by-token stream today (the CLI doesn't expose one in `-p` mode). If you want streamed tokens, point the picker at a [local LLM](local-llms.md) or the [Anthropic API](anthropic-api.md).
