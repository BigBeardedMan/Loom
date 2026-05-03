# Install

Loom ships as a `.dmg` from GitHub Releases. macOS 14 (Sonoma) or later.

## Steps

1. Grab the latest `Loom-<version>.dmg` from [Releases](https://github.com/BigBeardedMan/Loom/releases/latest).
2. Open the DMG.
3. Drag **Loom** onto the **Applications** alias inside the mounted volume.
4. Eject the volume.

## First launch — Gatekeeper

The build is **ad-hoc signed**, not Developer ID-signed. macOS will refuse to launch it on the first try with a "Loom can't be opened because Apple cannot check it for malicious software" dialog.

Bypass once:

- Right-click **Loom** in `/Applications` → **Open** → confirm in the dialog.

Subsequent launches are normal. Only the first launch needs the bypass.

## Updates

Once Loom is running, it polls GitHub Releases on a **60-second interval** and stages new builds in the background. When a newer release is available, the **Update** pill in the top bar lights up — click it to swap in the new version. See [Auto-update](../updates/auto-update.md) for the mechanics.

You can also force a remote check via **Help → Check for Updates…**.

## Uninstall

Drag `/Applications/Loom.app` to the Trash. Loom's data lives in:

- `~/Library/Application Support/Loom/` — staging directory and update manifest.
- `~/Library/Containers/` — none; Loom is unsandboxed.
- `~/Library/Application Support/com.chasesims.Loom/` — SwiftData store (workspaces, tasks, notes).
- macOS Keychain, service `com.chasesims.Loom` — Anthropic API key, local-endpoint auth tokens.

See [File paths](../reference/file-paths.md) for the full list.
