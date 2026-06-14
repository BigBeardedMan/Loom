# Install

Loom Testing Edition ships as a `.dmg` from GitHub prereleases. macOS 14 (Sonoma) or later.

## Steps

1. Grab the latest `LoomTestingEdition-<version>.dmg` from the newest `testing-*` prerelease on [Releases](https://github.com/BigBeardedMan/Loom/releases).
2. Open the DMG.
3. Drag **Loom Testing Edition** onto the **Applications** alias inside the mounted volume.
4. Eject the volume.

## First launch — Gatekeeper

The build is **ad-hoc signed**, not Developer ID-signed. macOS may refuse to launch it on the first try with a "Loom Testing Edition can't be opened because Apple cannot check it for malicious software" dialog.

Bypass once:

- Right-click **Loom Testing Edition** in `/Applications` -> **Open** -> confirm in the dialog.

Subsequent launches are normal. Only the first launch needs the bypass.

## Updates

Once Loom Testing Edition is running, it polls GitHub prereleases on a **60-second interval** and stages new builds in the background. When a newer testing release is available, the **Update Available** pill in the top bar lights up. See [Auto-update](../updates/auto-update.md) for the mechanics.

You can also force a remote check via **Help → Check for Updates…**.

## Uninstall

Drag `/Applications/Loom Testing Edition.app` to the Trash. Testing Edition data lives in:

- `~/Library/Application Support/Loom Testing Edition/` — staging directory, update manifest, shell history, transcripts, and helper state.
- `~/Library/Containers/` — none; Loom is unsandboxed.
- `~/Library/Application Support/com.chasesims.LoomTestingEdition/` — SwiftData store (workspaces, tasks, notes).
- macOS Keychain, service `com.chasesims.LoomTestingEdition` — Anthropic API key, local-endpoint auth tokens.

See [File paths](../reference/file-paths.md) for the full list.
