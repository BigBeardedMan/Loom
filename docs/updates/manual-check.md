# Manual update check

For when you don't want to wait for the 60-second poll.

## How

**Help → Check for Updates…** in the menu bar.

On macOS, that triggers `UpdateService.checkRemoteAndAnnounce()`, which:

1. Hits the GitHub API now (not on the next polling tick).
2. If a newer release is found, runs the same staging flow as the auto-update path. See [Auto-update](auto-update.md).
3. Surfaces a system alert with the result either way:
   - "Loom Testing Edition 9.0.14 (104) is ready. Click Update Available in the top bar to install and relaunch." (newer found)
   - "You're running 9.0.14 (104)." (already current)

On Windows, clicking the status-bar update segment or top **Update Available** pill checks the published `latest-windows-testing.json` manifest and opens the updater modal when a newer installer is available.

## When to use it

- You just published a Testing Edition release with `bin/release-testing.sh` and want to test the staging path right away.
- You suspect the auto-poller is wedged (it isn't, but the manual check is the fastest sanity check).
- You want the alert dialog feedback — auto-update is silent until the pill lights up.

## Disable state

The menu item is disabled while a remote check is in flight. It re-enables when the request completes.
