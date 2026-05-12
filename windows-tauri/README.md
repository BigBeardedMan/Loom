# Loom for Windows (Tauri port)

Native Windows build of [Loom](../README.md). Same product surface, different stack:

- Rust backend with `portable-pty` (ConPTY), `rusqlite`, `keyring` (Windows Credential Manager), `reqwest` (rustls), `notify`.
- React + TypeScript frontend in a WebView2 webview, built with Vite, styled with Tailwind v4. xterm.js for terminals, Monaco for code, CodeMirror for notes.
- Bundled as **MSI** and **NSIS** installers for both **`x86_64-pc-windows-msvc`** and **`aarch64-pc-windows-msvc`**.

## Local development (on macOS)

```bash
cd ~/Documents/Xcode/Loom/windows-tauri
pnpm install
pnpm tauri dev          # runs against macOS for fast UI iteration
```

UI changes hot-reload. Anything touching PTY, Credential Manager, or Windows-specific APIs will only work in a real Windows build.

## Building Windows artifacts

**Two reliable paths. Pick one.**

### A. Build inside the Win11 ARM VM (recommended)

One-time setup inside the VM:

```powershell
winget install Microsoft.EdgeWebView2Runtime
winget install Microsoft.VisualStudio.2022.BuildTools --override "--add Microsoft.VisualStudio.Workload.VCTools"
winget install Rustlang.Rust.MSVC
winget install OpenJS.NodeJS.LTS
npm install -g pnpm
rustup target add aarch64-pc-windows-msvc x86_64-pc-windows-msvc
```

Then, with the repo accessible (e.g. via VMware shared folder mapped to `Z:\`):

```powershell
cd Z:\loom-source\windows-tauri
pnpm install
pnpm tauri build --target aarch64-pc-windows-msvc
pnpm tauri build --target x86_64-pc-windows-msvc
```

Win11 ARM produces both ARM and x64 MSI/NSIS in one VM.

### B. GitHub Actions (zero local setup)

As of v3.0.0, Loom uses unified `vX.Y.Z` tags for both Mac and Windows. The workflow at `.github/workflows/windows-release.yml` runs on `windows-2022` and `windows-11-arm64` runners and appends NSIS installers + `latest-windows.json` to the same GitHub Release the Mac local build publishes its DMG to.

```bash
# From the repo root (Mac):
bin/release.sh
# This bumps the tag, pushes it, builds + uploads the DMG, and the Windows
# CI build kicks off on the same tag and uploads the NSIS installers.
```

Legacy `windows-v*.*.*` tags still trigger the workflow for older release flows; new releases should use the unified `v*` scheme.

### Why not cross-compile from macOS?

We installed `cargo-xwin`, `brew install llvm nsis`, the `*-pc-windows-msvc` rustup targets, and wired `src-tauri/.cargo/config.toml` to point `CC_<target>` at Homebrew's `clang-cl`. The build still fails compiling `ring`'s C code because cc-rs hardcodes a `clang` invocation path on this target combination. There's an open path involving forcing reqwest off `rustls` (its default TLS uses `ring`) onto `native-tls` (Windows SChannel), but that's a larger change. Until that lands, **fastest Mac-side iteration is `pnpm tauri dev` against macOS itself** (catches React/IPC bugs in seconds), and **release builds happen in the VM or CI**.

## Mac-side dev loop

```bash
cd ~/Documents/Xcode/Loom/windows-tauri
pnpm install
pnpm tauri dev          # runs against macOS for fast UI iteration
```

UI changes hot-reload. Anything touching ConPTY, Windows Credential Manager, or PowerShell shell integration only exercises in a real Windows build, so test those in the VM.

Output:
```
src-tauri/target/<triple>/release/bundle/
├── msi/Loom_<version>_<arch>.msi
└── nsis/Loom_<version>_<arch>-setup.exe
```

## Testing

See [TESTING.md](./TESTING.md) for the VMware Fusion + Win11 ARM setup and full smoke checklist.

## Releases

Unified `vX.Y.Z` tags trigger `.github/workflows/windows-release.yml`. The workflow builds on `windows-2022` and `windows-11-arm64` runners and appends NSIS installers + `latest-windows.json` to the unified GitHub Release (the Mac DMG is built locally by `bin/release.sh` and attached to the same release).

## Project layout

```
windows-tauri/
├── src/                  React + TypeScript frontend
│   ├── lib/              IPC bridge, zustand store, theme
│   ├── modules/          One folder per macOS module (workspace, terminal, editor, kanban, notes, agents, build, settings)
│   ├── components/       Cross-cutting UI (titlebar, etc.)
│   └── styles/global.css Tailwind v4 entry + xterm CSS + theme tokens
└── src-tauri/            Rust backend
    ├── src/
    │   ├── lib.rs        Tauri Builder, plugin wire-up, command registration
    │   ├── state.rs      AppState (db pool, terminal registry, etc.)
    │   ├── db/           SQLite mirror of SwiftData models
    │   ├── terminal/     portable-pty session registry + ConPTY foreground detection
    │   ├── agents/       Anthropic SSE, CLI runner, claude agents list parser, MCP shell-out
    │   ├── keychain.rs   Credential Manager bridge
    │   ├── updater.rs    tauri-plugin-updater commands
    │   └── shell_integration/  PowerShell profile shim writing history JSONL
    ├── migrations/       SQL migrations
    ├── capabilities/     Tauri ACL
    └── tauri.conf.json   bundle, window, plugin config
```

## Feature parity with macOS

As of v3.0.0 Loom is one product with one version across both platforms.
The split-versioning era (macOS at 2.x, Windows at 1.x) ended once macOS
2.5.0 backported the three Windows-side features that closed the parity
loop (crash reporter, editor file watcher, editor syntax highlighting).
Going forward, every `vX.Y.Z` tag publishes a single GitHub Release with
both the Mac DMG and the Windows NSIS installers for x64 and ARM64.

Across both platforms the surface is:

- Workspace shell — sidebar with rename, kind icons, per-workspace session
  count; cockpit with dynamic blocks, drag-anywhere-on-the-titlebar to
  reorder or pin (8-edge drop targets: left, right, top, bottom, plus four
  corners), draggable seams between blocks and on pin boundaries for
  per-block resize, double-click a seam to reset, right-click the deck for
  Reset Grid Layout, block rename, full-row span toggle (right-click),
  close, status dot.
- Terminal pane — multi-pane splits (1 / 2-H / 2-V / 3-H / 3-V / 2×2 quad),
  per-pane header with cwd + OSC title, Ctrl+C button, foreground command
  polling, shell-integration history writer.
- Editor pane — Monaco editor, file watcher with reload-from-disk prompt,
  dirty status, Ctrl+S save, file tree.
- Tasks pane — live mirror of Claude / Codex CLI agent task files.
- Agent pane — Anthropic API (direct streaming), Claude CLI, Codex, Gemini,
  Ollama, OpenAI-compat endpoints; per-workspace vendor/model persistence;
  cancel-while-streaming.
- Notes pane — multi-note tabs, CodeMirror markdown body, autosave.
- Preview pane — URL bar with back/forward/refresh, iframe, load-failure
  overlay.
- Commands pane — surfaces the PowerShell shell-integration JSONL with copy
  + send-to-terminal actions and a workspace-only filter.
- Settings — Appearance, AI Providers (Anthropic key + local endpoint CRUD
  with test-connection), MCP (add / remove / refresh), Shell, Tasks (stale
  window picker), Advanced (reveal data folder, log viewer, reset UI
  state), About.
- Usage chips — Claude / Codex / Gemini chip → full dashboard with stat
  grid, donuts, hour-of-day heatmap, recent prompts, top topics, top
  projects; timeframe picker persists.
- Updater — arch-aware (handles ARM64 emulation), downloads matching NSIS
  installer to `%APPDATA%\com.chasesims.Loom\staging\` with live progress.
  One click on the green Update pill runs the full flow: download, silent
  NSIS `/S` install via a detached `%TEMP%\loom-update-<pid>.bat` helper
  that waits for the running Loom to exit, then relaunches the fresh
  build. No installer wizard, no uninstall step.
- Crash reporter — Rust panic hook + React ErrorBoundary surface a modal
  on next launch with copy + "Report on GitHub" deep link.
- Keyboard — Ctrl+K palette, Ctrl+T add terminal, Ctrl+W close, Ctrl+N
  new workspace, Ctrl+Shift+L cycle theme, Ctrl+Shift+1..7 add by kind,
  Ctrl+Shift+O previous workspace, Ctrl+Alt+F full-row, Ctrl+1..9 jump.
- Command palette — workspaces, add-block actions, recent commands rerun,
  Open Settings.

Deferred to follow-ups:

- Multi-window support
- Notes Ctrl+F search
- Auto-preview index per Preview block
- Toast notifications, tray icon, jump lists
- Update minisign keypair signing (current updater uses arch-detected
  download + user confirmation in place of signature verification)
