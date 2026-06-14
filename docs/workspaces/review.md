# Review workspace

For looking at something rendered - a localhost preview, a GitHub PR, a deployed page - alongside an agent and the adaptive review rail.

Sidebar label: **Review** · icon: `magnifyingglass`.

## Available panes

- **Preview** (⌘⇧1) — In-app web view. Type a URL in the address bar and hit **Go**.
- **Agent** (⌘⇧2) — Tool-running agent pane scoped to the preview target and workspace folder.

## Preview pane

The Preview pane is a `WKWebView` with:

- Address bar (typed URL, ↩ or **Go** to navigate).
- Back / forward / reload controls.
- A small status indicator on the title bar.

Common targets:

- `http://localhost:3000` — Next.js dev server.
- `http://localhost:1234` — LM Studio's UI (if you happen to want to look at it).
- `https://github.com/...` — PR diff view.

## Why Review is its own room

A Review workspace deliberately keeps the deck focused on preview plus agent. Review evidence still appears in the right rail: changed files, check status, preview signals, failed tools, and ship-decision context from recorded run ledgers. If you find yourself reaching for a terminal, switch to Prompt or Runs.

## Sessions and review evidence

Review does not default to a Runs pane, but the shell can still show review-ready run evidence in the right rail when graph ledgers exist under `~/.loom/agent-runs/<rootRunId>/events.jsonl`.
