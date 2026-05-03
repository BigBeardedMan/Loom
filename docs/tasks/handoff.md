# Task → Agent / Terminal handoff

Kanban cards can carry the next action — a prompt or a shell command — and dispatch it to the right pane in one click.

## Two handoff fields

Every card has two optional fields:

- `agentPrompt` — the text you'd type into the Agent pane.
- `terminalCommand` — the shell command you'd run.

Set them in the card inspector. Either or both can be filled.

## Sending to the Agent pane

In the card inspector or the card's context menu, click **Send to agent**. Loom:

1. Grabs `agentPrompt`.
2. Auto-fills the Agent pane's input.
3. Submits the prompt.
4. Optionally selects the configured `agentName` in the picker (passed as `--agent` for Claude Code).

If no Agent pane is open in the current workspace, Loom adds one first.

## Sending to the Terminal pane

Click **Send to terminal**. Loom:

1. Grabs `terminalCommand`.
2. Auto-injects it into the focused Terminal pane (typed character-by-character into the foreground process's stdin).
3. Sends a newline so the command runs.

If no Terminal pane is open, Loom adds one first.

## Bulk handoff

There's no "send all Todo cards to agent" today. The pattern is one card → one handoff so the pane state stays legible. If you need a multi-step plan, put it in `taskKnowledge` and let the agent decompose it.

## Why two separate fields?

Some tasks are pure conversation ("Have the agent draft a release note"). Some are pure execution ("Run the migration script"). And some are both — set both fields, fire one then the other. Keeping the two pipelines separate avoids gymnastics about whether a string is a prompt or a command.
