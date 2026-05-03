# Review workspace

For looking at something rendered — a localhost preview, a GitHub PR, a deployed page — alongside an agent. Two panes only.

Sidebar label: **Review** · icon: `magnifyingglass`.

## Available panes

- **Preview** (⌘⇧1) — In-app web view. Type a URL in the address bar and hit **Go**.
- **Agent** (⌘⇧2) — Chat pane.

## Preview pane

The Preview pane is a `WKWebView` with:

- Address bar (typed URL, ↩ or **Go** to navigate).
- Back / forward / reload controls.
- A small status indicator on the title bar.

Common targets:

- `http://localhost:3000` — Next.js dev server.
- `http://localhost:1234` — LM Studio's UI (if you happen to want to look at it).
- `https://github.com/...` — PR diff view.

## Why Review is its own kind

A Review workspace deliberately doesn't expose the Tasks pane or the Terminal pane. It's a "look at this and ask the agent about it" surface, not a build cockpit. If you find yourself reaching for a terminal here, switch to a Prompt workspace.

## Sessions

Review workspaces show "Review workspaces don't have sessions yet." in the sidebar's session list — sessions are tied to the Tasks pane, which Review doesn't have.
