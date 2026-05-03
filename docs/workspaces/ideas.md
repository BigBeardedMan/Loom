# Ideas workspace

Lightweight workspace for capturing notes and brainstorming with an agent. Two panes only.

Sidebar label: **Ideas** · icon: `lightbulb`.

## Available panes

- **Notes** (⌘⇧1) — Note list on the left (within the pane), markdown-style body on the right. Backed by SwiftData (`IdeaNote` model) with autosave.
- **Agent** (⌘⇧2) — Same agent pane as Prompt; useful for thinking through an idea without spinning up a terminal.

## Notes structure

Each note has:

- A title (first line of the body, auto-derived).
- A body (plain text, soft-wrapped, monospaced).
- Last-edited timestamp surfaced as `edited <relative time>`.

Notes are not workspace-scoped — every Ideas workspace shares the same note pool, but the active selection is per-workspace.

## Agent integration

The Agent pane in Ideas works the same as in Prompt:

- Default provider: Claude Code via OAuth.
- Local LLMs work too — point at Ollama or any OpenAI-compatible endpoint via [Settings → Providers](../settings/providers.md).
- `cwd` is the workspace folder if set, otherwise nil.
- Every turn carries a workspace snapshot — workspace name, project folder, `CLAUDE.md`/`AGENTS.md`/`GUIDE.md`/`README.md` from that folder, the active tab's body, and short excerpts of sibling tabs — so asking for ideas is grounded in the project, not generic. See [Agents → Workspace context block](../agents/overview.md#workspace-context-block) for the full payload shape.

### Save-to-tab proposal cards

When the agent's response in an Ideas workspace looks like a list (numbered or bulleted, three or more items), an inline confirmation card appears under the response:

- Title: `N ideas for "<active tab name>"`.
- Each item rendered as a checkbox row — uncheck items you don't want.
- Mode toggle: **Create as new tabs** (one new note per item) or **Append to active tab** (bullets added to the current note's body).
- `Add N ideas` commits the selected items via SwiftData; `Dismiss` collapses the card.

The card is gated by the active workspace kind. Other kinds (Prompt, Review) ignore proposals and render the response as plain text.

For Anthropic-direct providers, items are produced via the `propose_items` tool. For Claude Code subprocess and local HTTP providers, a fallback list parser extracts items from the finalized response — phrasing requests like "give me 8 ideas for X" reliably triggers the card.

## When to use Ideas vs Prompt

| Use Ideas when… | Use Prompt when… |
| --------------- | ---------------- |
| Drafting copy, planning, journaling | Running commands, editing files |
| Bouncing rough ideas off a model | Driving an agent against a real codebase |
| You don't need a terminal or kanban | You need full cockpit panes |
