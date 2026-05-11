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

Tag the repo with `windows-v0.x.y`. The workflow at `.github/workflows/windows-release.yml` runs on `windows-2022` and `windows-11-arm64` runners and attaches MSIs + NSIS installers to a GitHub Release plus a `latest-windows.json` updater manifest.

```bash
git tag windows-v0.1.0
git push origin windows-v0.1.0
```

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

Tag the repo with `windows-v0.x.y` to trigger `.github/workflows/windows-release.yml`. The workflow builds on `windows-2022` and `windows-11-arm64` runners and attaches MSIs + NSIS to a GitHub Release.

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

## What is intentionally not ported yet

The first cut covers core flows. These macOS Loom features will land in follow-ups:

- LiveAgentTasks (Codex/Claude rollout watcher)
- Per-CLI usage scrapers (UsageService)
- Multi-pane terminal splits inside a single tab (currently tab-based)
- Custom DMG-style installer chrome (NSIS default ships)
- Auto-update minisign keypair generation (run `tauri signer generate` and paste pubkey into `tauri.conf.json` before first release)
