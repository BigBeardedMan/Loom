# Auto-update

Loom Testing Edition checks GitHub Releases on a 60-second interval and stages new builds in the background. The **Update Available** pill in the top bar lights up when a newer testing release is ready to install.

## Cadence

- **macOS remote poll:** every 60 seconds against recent `testing-*` GitHub prereleases.
- **macOS local manifest poll:** every 4 seconds (cheap; just stats the staging directory).
- **Windows remote poll:** every 60 seconds against `latest-windows-testing.json` from the current testing prerelease.
- **Repository:** `BigBeardedMan/Loom`.

## macOS hit

1. `GitHubReleaseFetcher.fetchLatestPrerelease()` finds the newest `testing-<version>` prerelease with a higher semver than the running app.
2. `UpdateService` downloads the Testing Edition `.dmg` to a temp file.
3. The DMG is mounted with `hdiutil attach`, the `.app` bundle is copied to `~/Library/Application Support/Loom Testing Edition/staging/Loom Testing Edition.app`, then the DMG is detached.
4. A `manifest.json` is written next to the staged bundle (`version`, `build`, `stagedAt`).
5. `UpdateService.available` flips, lighting the **Update Available** pill.

## Windows hit

1. The app reads `latest-windows-testing.json`.
2. The manifest points to the exact versioned NSIS installer for the current architecture.
3. The updater verifies the installer signature, downloads it, stages it, and runs the NSIS updater helper.

## Click the pill

On macOS, clicking the pill calls `applyAndRelaunch()`:

1. Spawns a small detached helper script.
2. The helper waits for the running Loom process to exit.
3. The helper swaps `/Applications/Loom Testing Edition.app` with the staged bundle.
4. The helper relaunches Loom Testing Edition from `/Applications`.

On Windows, clicking the pill opens the update modal, downloads the installer, and hands it to the silent updater helper. The helper closes Loom, installs the update, and relaunches.

## Where state lives

- macOS staging directory: `~/Library/Application Support/Loom Testing Edition/staging/Loom Testing Edition.app`
- macOS manifest: `~/Library/Application Support/Loom Testing Edition/staging/manifest.json`
- Windows manifest asset: `https://github.com/BigBeardedMan/Loom/releases/download/testing-<version>/latest-windows-testing.json`
- Last-seen macOS tag: in-memory only (re-fetched on relaunch).

## Manual check

Use **Help → Check for Updates…** to force a remote poll right now. Same path; just bypasses the 60-second interval.

## Disabling

There's no UI toggle to disable auto-update today. If you need to stop it, quit Loom and remove `~/Library/Application Support/Loom Testing Edition/staging/`. To prevent staging on relaunch, edit `Loom/App/UpdateService.swift` and short-circuit `start()` before rebuilding.

## Why 60 seconds?

The 60-second cadence trades a few extra HTTP requests for a tighter "I just shipped a build, switch over fast" loop on a single-user app. The Testing Edition prerelease filter keeps stable Loom releases out of the Testing Edition update pill.
