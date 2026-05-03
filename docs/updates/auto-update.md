# Auto-update

Loom checks GitHub Releases on a 60-second interval and stages new builds in the background. The **Update** pill in the top bar lights up when a newer release is staged — click it to swap in the new version.

## Cadence

- **Remote poll:** every 60 seconds.
- **Local manifest poll:** every 4 seconds (cheap; just stat's the staging directory).
- **API endpoint:** `https://api.github.com/repos/BigBeardedMan/Loom/releases/latest` (unauthenticated, 60 req/hr per IP — fits fine in the cadence).

## What happens on a hit

1. `GitHubReleaseFetcher.fetchLatest()` returns a release with a higher semver tag than the running build.
2. `UpdateService` downloads the `.dmg` to a temp file.
3. The DMG is mounted with `hdiutil attach`, the `.app` bundle is copied to `~/Library/Application Support/Loom/staging/Loom.app`, then the DMG is detached.
4. A `manifest.json` is written next to the staged bundle (`version`, `build`, `stagedAt`).
5. The `UpdateService.available` flag flips, lighting the Update pill.

## Click the pill

Clicking the pill calls `applyAndRelaunch()`:

1. Spawns a small detached helper script.
2. The helper waits for the running Loom process to exit.
3. The helper swaps `/Applications/Loom.app` with the staged bundle.
4. The helper relaunches Loom from `/Applications`.

The hand-off is fast — Loom quits, the new build launches in well under a second.

## Where state lives

- Staging directory: `~/Library/Application Support/Loom/staging/Loom.app`
- Manifest: `~/Library/Application Support/Loom/staging/manifest.json`
- Last-seen tag: in-memory only (re-fetched on relaunch).

## Manual check

Use **Help → Check for Updates…** to force a remote poll right now. Same path; just bypasses the 60-second interval.

## Disabling

There's no UI toggle to disable auto-update today. If you need to stop it, kill the Loom process and remove `~/Library/Application Support/Loom/staging/`. To prevent staging on relaunch, edit `Loom/App/UpdateService.swift` and short-circuit `start()` before rebuilding.

## Why 60 seconds?

Earlier versions polled every 30 minutes. The 60-second cadence (introduced in v1.0.2) trades a few extra HTTP requests for a tighter "I just shipped a build, switch over fast" loop on a single-user app. Unauthenticated rate limits accommodate it easily.
