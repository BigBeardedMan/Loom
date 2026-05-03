# Loom

Native macOS workspace for terminals, editor, AI agents, and task state in one window. The terminal is the differentiator.

Loom is a personal, single-user tool. No subscription model, hosted control plane, team billing, or feature gating. Local-first storage is the default; cloud services are optional provider integrations only when they directly help the operator ship.

![Loom — four-pane cockpit: editor, terminal, agent, task board](images/Loom1.jpg)

![Loom — Notes workspace with agent pane](images/Loom2.jpg)

![Loom — Preview workspace with live localhost preview and agent pane](images/Loom3.jpg)

## Where to start

- New here? Read [Install](getting-started/install.md), then [First run](getting-started/first-run.md).
- Want to wire up your local model? See [Local LLMs](agents/local-llms.md).
- Cutting a build? See [Cutting a release](releasing/cutting-a-release.md).

## What's in Loom

| Area | Summary |
| ---- | ------- |
| [Workspaces](workspaces/overview.md) | Three kinds — Prompt, Ideas, Review — each with its own pane lineup. |
| [Agents](agents/overview.md) | Claude Code via OAuth subprocess, optional Anthropic API key, plus local LLMs over HTTP. |
| [Tasks](tasks/overview.md) | SwiftData kanban with task → agent and task → terminal handoff. |
| [Terminal](terminal/overview.md) | SwiftTerm-backed pane with CLI agent auto-detection. |
| [Editor](editor/overview.md) | File tree with breadcrumb. CodeEdit integration is on the roadmap. |
| [Settings](settings/appearance.md) | Theme, stale-task window, local providers, Anthropic key. |
| [Updates](updates/auto-update.md) | Polls GitHub Releases on a 60s interval; Update pill swaps in the new build. |
| [Releasing](releasing/cutting-a-release.md) | `bin/release.sh` ships a signed-ish DMG and tags the commit. |

## Product principles

- **Personal command center first.** Optimize for one builder moving quickly, not tenant management.
- **Local-first by default.** Tasks, settings, workspace metadata, and agent configuration live on this Mac unless explicitly synced.
- **Bring your own providers.** API keys live in Keychain; model and provider integrations stay replaceable.
- **No artificial tiers.** If Loom can do something locally, it should be available.
- **Terminal work should be reviewable.** Commands, output, exit status, and agent actions become structured history over time.
