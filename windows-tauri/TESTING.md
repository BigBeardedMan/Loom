# Testing Loom for Windows on a Mac

You build the app on macOS and run it inside a Windows 11 ARM VM. Win11 ARM emulates x64 transparently via xtajit64, so one VM covers both `aarch64` and `x86_64` MSI/NSIS artifacts.

## One-time VM setup (about 25 minutes)

1. **Download Windows 11 ARM64 disk image.** https://www.microsoft.com/software-download/windows11arm64. Choose the ARM64 VHDX or ISO.
2. **Install VMware Fusion** (free Personal license). https://www.vmware.com/products/desktop-hypervisor. Sign in with a Broadcom account if prompted.
3. **Create a new VM** in Fusion:
   - File then New, choose "Install from disc or image"
   - Select the downloaded ISO
   - VM specs: 8 GB RAM, 4 vCPU, 64 GB disk, ARM architecture (auto-selected)
   - Encryption: none (or set a password if you prefer)
4. **OOBE local account workaround.** On the network screen, press Shift+F10 to open cmd, then type `OOBE\BYPASSNRO` and press Enter. The VM reboots and lets you skip network sign-in so you can create a local account.
5. **Install VMware Tools** when prompted (resolution scaling, clipboard, shared folders).
6. **Install WebView2 runtime** inside the VM (Tauri prerequisite):
   ```powershell
   winget install Microsoft.EdgeWebView2Runtime
   ```
7. **Optional, only if you also want to build inside the VM:**
   ```powershell
   winget install Microsoft.VisualStudio.2022.BuildTools --override "--add Microsoft.VisualStudio.Workload.VCTools"
   winget install Rustlang.Rust.MSVC
   winget install OpenJS.NodeJS.LTS
   npm install -g pnpm
   ```

## Shared folder

In Fusion: select the VM, Settings, Sharing, then add a folder mapping:

| Mac path | VM mount |
| --- | --- |
| `~/Documents/Xcode/Loom/windows-tauri/src-tauri/target/` | `Z:\loom-build` |

VMware Tools must be running for the mapping to appear inside the VM.

## Building on Mac

The MSVC toolchain is brittle to cross-compile from macOS. We have two paths:

### Path A: cargo-xwin from Mac (fast iteration)

```bash
brew install nsis
cargo install cargo-xwin
cd ~/Documents/Xcode/Loom/windows-tauri
pnpm tauri build --target aarch64-pc-windows-msvc --runner "cargo-xwin"
pnpm tauri build --target x86_64-pc-windows-msvc --runner "cargo-xwin"
```

Output lands at:
- `src-tauri/target/aarch64-pc-windows-msvc/release/bundle/msi/Loom_*.msi`
- `src-tauri/target/x86_64-pc-windows-msvc/release/bundle/msi/Loom_*.msi`

First run downloads ~1 GB of MSVC headers. Subsequent builds are quick.

### Path B: Build inside the VM (reliable)

```powershell
# Inside the VM:
git clone https://github.com/BigBeardedMan/Loom (or copy via shared folder)
cd Loom\windows-tauri
pnpm install
pnpm tauri build --target aarch64-pc-windows-msvc
pnpm tauri build --target x86_64-pc-windows-msvc
```

This is what GitHub Actions does and produces the canonical release artifacts.

## Installing in the VM

1. In Explorer, open `Z:\loom-build\aarch64-pc-windows-msvc\release\bundle\msi\`
2. Right-click the `.msi` and Install
3. SmartScreen will warn ("unrecognized publisher"). Click **More info** then **Run anyway**. This is the same Gatekeeper-style first-launch friction the macOS build has.
4. Loom launches automatically when install completes.

To test the x64 build, install the x64 MSI in the same ARM VM. Task Manager (View, Set columns, Architecture) will show "x64" under xtajit64 emulation. The app should behave identically.

## Smoke checklist

Run through these on first install:

- [ ] Window opens, titlebar shows "Loom"
- [ ] Workspaces sidebar visible on the left
- [ ] Click + to create a new workspace, pick a folder, choose a color and kind, hit Create
- [ ] Open a terminal pane and type `dir` then resize the window: layout reflows
- [ ] `claude --version` (if Claude CLI installed) prints version
- [ ] Add a Kanban card, then close and reopen the app: card persists
- [ ] Add a note in Ideas-kind workspace, restart: persists
- [ ] Settings, AI Providers, paste a fake API key (sk-ant-xxx), Save. Restart app, reopen Settings, key is still there: Credential Manager round-trip
- [ ] Ctrl+K opens command palette
- [ ] Create a Review-kind workspace and load `https://example.com` in Preview: renders
- [ ] Settings, Shell, Install: writes `Microsoft.PowerShell_profile.ps1`, no crash
- [ ] Quit and reinstall (Add/Remove Programs uninstall, then install fresh): workspaces, cards, notes, and stored keys survive

## CI builds (no VM needed)

Push a tag starting with `windows-v` to trigger `.github/workflows/windows-release.yml`. The workflow builds both architectures on Microsoft-hosted runners and publishes a GitHub Release with MSI/NSIS artifacts plus a `latest-windows.json` manifest the in-app updater polls.

```bash
git tag windows-v0.1.0
git push origin windows-v0.1.0
```

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| "WebView2 Runtime not found" on launch | Inside the VM: `winget install Microsoft.EdgeWebView2Runtime` |
| Terminal pane stays blank | Check Task Manager for a `pwsh.exe` or `cmd.exe` child of `loom.exe`. If absent, PowerShell is not on PATH. Install pwsh or change the default shell in Settings. |
| `claude.exe not found` in Agent pane | Install the Claude CLI: `npm install -g @anthropic-ai/claude-cli`, then restart Loom. |
| MSI install fails with code 1603 | Check `%TEMP%\MSI*.log` for the detailed error. Most often a stale leftover install: uninstall first via Add/Remove Programs. |
| Updater never picks up new version | Check `%LOCALAPPDATA%\Loom\logs\` for fetch errors. The endpoint must publish `latest-windows.json` with a valid signature for tauri-plugin-updater to apply. |
