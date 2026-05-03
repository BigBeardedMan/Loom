# Command injection

Loom can type commands into the Terminal pane on your behalf. Two paths today:

## From a kanban card

Set `terminalCommand` on a card → click **Send to terminal**. Loom:

1. Brings the focused Terminal pane to the front (or adds one).
2. Types the command character-by-character into the foreground process's stdin.
3. Sends a newline.

Because it's typed into stdin (not eval'd), the command runs in whatever shell context exists right now — your aliases, exported env, `cd`-ed directory, all apply.

## From the agent pane

Some sub-agents emit commands as their final answer. When the Agent pane sees a fenced shell block in the response, it adds a small **Run in terminal** button under the bubble. Click it to inject the command into the Terminal pane.

This is opt-in per click — Loom does not auto-execute model output.

## Caveats

- **No multi-line scripts.** If you paste a heredoc or a multi-line block, Loom types the whole thing as one stdin write. Most shells handle this fine, but anything that buffers per-line (e.g., a partially-typed `for` loop) can interleave oddly.
- **No password prompts.** Don't inject `sudo` commands and expect them to work — the password prompt won't be filled.
- **The shell sees it as user input.** History (`history`, ↑) records injected commands the same as typed ones.

## Safety

Loom does not execute injected commands without an explicit click. There is no "auto-run agent suggestions" mode. If you want one — file an issue, but the default will stay manual.
