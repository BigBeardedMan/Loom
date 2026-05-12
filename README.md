# Loom

Native workspace app for terminals, editor, AI agents, and task state in one window. The terminal is the differentiator.

Two builds live in this repo:

- **macOS** (this README): SwiftUI + SwiftData, ships as a `.dmg` to `/Applications/Loom.app`. Source under `Loom/`.
- **Windows** (`windows-tauri/`): Tauri 2 + Rust + React, ships as MSI/NSIS for both `aarch64-pc-windows-msvc` and `x86_64-pc-windows-msvc`. See [`windows-tauri/README.md`](./windows-tauri/README.md) and [`windows-tauri/TESTING.md`](./windows-tauri/TESTING.md).

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

## Product Principles

- Personal command center first. Optimize for one builder moving quickly, not tenant management.
- Local-first by default. Tasks, settings, workspace metadata, and agent configuration live on this Mac unless explicitly synced.
- Bring your own providers. API keys live in Keychain; model/provider integrations should stay replaceable.
- No artificial tiers. If Loom can do something locally, it should be available.
- Terminal work should be reviewable. Commands, output, exit status, and agent actions should become structured history over time.

## Versioning

Semver. Bump `MARKETING_VERSION` in `project.yml` on every meaningful build, then `xcodegen generate`.
