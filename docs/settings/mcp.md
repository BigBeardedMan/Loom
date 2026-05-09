# MCP

Loom's **Settings → MCP** tab manages the [Model Context Protocol](https://modelcontextprotocol.io) servers that your local Claude Code installation connects to.

Loom doesn't speak MCP directly. Every read and write here goes through the `claude mcp` CLI, so the source of truth stays inside Claude Code's own registry. Adding a server through Loom is identical to running `claude mcp add` in a terminal; the only difference is the UI.

## What you see

The list shows every server `claude mcp list` reports, with:

- **Status dot**: green for connected, orange for needs-authentication, red for failed, gray for unknown.
- **Transport label**: `stdio`, `HTTP`, or `SSE` (lifted from the CLI's parenthesized hint, e.g. `(HTTP)`).
- **Target**: the URL or stdio command Claude Code uses to reach the server.
- **Status line**: the raw human-readable status text from the CLI.

## Adding a server

Click **Add**, fill in:

- **Name**: a short identifier; this becomes the value Claude Code looks up internally.
- **Command**: the executable to run (`npx`, `uvx`, `python`, an absolute path, etc.).
- **Args**: space-separated arguments passed to the command. Empty is fine for servers that take none.

Loom invokes `claude mcp add <name> <command> -- <args...>`. The `--` separator stops the CLI from interpreting your server's flags as its own.

## Removing a server

The trash button on each row runs `claude mcp remove <name>`.

## When `claude` isn't installed

The tab surfaces an error if the `claude` binary isn't on disk at any of the standard locations (`/usr/local/bin/claude`, `/opt/homebrew/bin/claude`, `~/.local/bin/claude`). Install Claude Code first, then come back.

## Refresh

The tab refreshes automatically the first time you open it during a Loom session. Click **Refresh** to re-run `claude mcp list` and update the status of every server, which is useful after one of them comes back online.
