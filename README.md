# Loom

Native macOS workspace app for terminals, editor, AI agents, and task state in one window. The terminal is the differentiator.

Loom is a personal, single-user tool. No subscription model, hosted control plane, team billing, or feature gating. Local-first storage is the default; cloud services should be optional provider integrations only when they directly help the operator ship.

![Loom — four-pane cockpit: editor, terminal, agent, task board](docs/images/Loom1.jpg)

![Loom — Notes workspace with agent pane](docs/images/Loom2.jpg)

![Loom — Preview workspace with live localhost preview and agent pane](docs/images/Loom3.jpg)

## Install

Grab the latest `.dmg` from [Releases](https://github.com/BigBeardedMan/Loom/releases/latest), open it, and drag **Loom** to Applications. macOS 14+.

The build is ad-hoc signed (no Apple Developer ID), so on first launch right-click **Loom → Open** to bypass Gatekeeper's one-time prompt. Subsequent launches behave normally.

Loom auto-checks GitHub Releases every 60 seconds. When a newer build is available, the **Update** pill in the top bar lights up. Click it to swap in the new version.

## Build from source

```bash
brew install xcodegen          # one-time
cd path/to/Loom                # your local clone
xcodegen generate              # regenerate Loom.xcodeproj after editing project.yml
open Loom.xcodeproj
```

Then build & run from Xcode (⌘R). macOS 14+.

## Cutting a release

```bash
# 1. Bump MARKETING_VERSION (and CURRENT_PROJECT_VERSION) in project.yml
# 2. Commit + push
bin/release.sh                 # run from the repo root
```

`release.sh` regenerates the project, builds Release, packages a `.dmg`, tags `vX.Y.Z`, pushes the tag, and creates a GitHub release with the `.dmg` attached. Running Loom installs everywhere pick the new build up automatically.

## Docs

- **Single-page reference:** [GUIDE.md](./GUIDE.md). Every feature, every setting, every file path, every keyboard shortcut. Has a table of contents at the top.
- **Hosted MkDocs site:** [bigbeardedman.github.io/Loom](https://bigbeardedman.github.io/Loom/). Same chapters, navigable per-page.

## Status

`v1.8.0`. Four-pane cockpit, SwiftTerm-backed terminal with **multi-row click-to-position inside CLI agent prompts**, Anthropic + Claude Code agents, **local LLMs (Ollama + OpenAI-compatible)**, MkDocs docs site at [bigbeardedman.github.io/Loom](https://bigbeardedman.github.io/Loom/), SwiftData task board with task-to-agent / task-to-terminal handoff, and over-the-air updates from GitHub Releases with **SHA-256 verified DMGs** (auto-update refuses to install a release without a published checksum sidecar). **Stable local code signing** so granted folder permissions persist across rebuilds, and a **giant throbber on the Usage view** while year-range snapshots compute. v1.4.0 landed a security/correctness pass: hardened Keychain access flags, stripped credential env vars on PTY spawn, an arguments-array `claude` invocation (no shell), terminated-process cancel that actually unblocks, and off-main-thread tasks/usage/layout writes. v1.5.0 added rolling usage windows and dashboard analytics. v1.6.0 split Usage into per-CLI dashboard tabs. v1.7.0 added Codex and Gemini CLI support. v1.7.1 is a re-release of v1.7.0 to trigger the auto-updater (a build-only bump in v1.7.0 left the version string unchanged, so clients didn't pick it up). v1.8.0 makes the Agent pane **workspace-aware** — every prompt now ships the workspace name, project folder path, project memory (CLAUDE.md / AGENTS.md / GUIDE.md / README.md from the workspace folder), the active idea tab's contents, and sibling tab summaries — so asking "give me ideas" actually grounds in the project you're sitting in. Command-block terminal history, multi-pane terminal layouts, MCP, and CodeEdit integration land in subsequent versions.

## Product Principles

- Personal command center first. Optimize for one builder moving quickly, not tenant management.
- Local-first by default. Tasks, settings, workspace metadata, and agent configuration live on this Mac unless explicitly synced.
- Bring your own providers. API keys live in Keychain; model/provider integrations should stay replaceable.
- No artificial tiers. If Loom can do something locally, it should be available.
- Terminal work should be reviewable. Commands, output, exit status, and agent actions should become structured history over time.

## Versioning

Semver. Bump `MARKETING_VERSION` in `project.yml` on every meaningful build, then `xcodegen generate`.
