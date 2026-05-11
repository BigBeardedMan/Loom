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

## Building Windows artifacts from macOS

One-time setup:

```bash
rustup target add aarch64-pc-windows-msvc x86_64-pc-windows-msvc
cargo install cargo-xwin
brew install llvm nsis
```

The `llvm` install gives you `clang-cl`, `llvm-lib`, and `llvm-rc`, which are required for crates with C bindings (notably `ring` via reqwest's rustls). `src-tauri/.cargo/config.toml` points to those binaries.

Build:

```bash
cd ~/Documents/Xcode/Loom/windows-tauri/src-tauri
cargo xwin build --release --target aarch64-pc-windows-msvc
cargo xwin build --release --target x86_64-pc-windows-msvc
```

For full MSI/NSIS packaging (not just the bare `.exe`), use Tauri's bundler with the Windows targets. Tauri's bundler invokes WiX/NSIS, which is more reliable inside the Win11 VM than on macOS. See [TESTING.md](./TESTING.md) for the VM-side build path.

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
