# Loom Testing Edition

A separate release channel of Loom that lives on the `loom-testing-edition` branch. Same feature surface as main, just shipped under a different identity so you can run pre-release builds side-by-side with the main install and not lose your workspaces, settings, or Keychain items.

## What differs from main

| | Main Loom | Testing Edition |
| --- | --- | --- |
| Bundle ID (Mac) | `com.chasesims.Loom` | `com.chasesims.LoomTestingEdition` |
| Tauri identifier (Windows) | `com.chasesims.Loom` | `com.chasesims.LoomTestingEdition` |
| App display name | `Loom` | `Loom Testing Edition` |
| Install location (Mac) | `/Applications/Loom.app` | `/Applications/Loom Testing Edition.app` |
| Data folder (Mac) | `~/Library/Application Support/Loom/` | `~/Library/Application Support/Loom Testing Edition/` |
| Keychain service | `com.chasesims.Loom` | `com.chasesims.LoomTestingEdition` |
| Versioning scheme | semver `3.2.1` | semver `3.3.0` (always ≥ one minor ahead of latest stable) |
| Release tag | `v3.2.1` | `testing-3.3.0` |
| GitHub release flag | latest | pre-release |
| Updater | walks `/releases/latest` for `v*` tags | walks `/releases?per_page=30` and picks newest `testing-*` (skipped by `/releases/latest`) |

The two installs cannot see each other's data, keys, or workspaces. Treat them as separate apps that happen to share a repo.

## Versioning

Testing Edition uses semver, kept at least one minor ahead of the latest stable Loom release. The pill in the running app shows e.g. `3.3.0`, not a SHA — same shape as main, just a higher number. The updater compares versions with strict semver ordering, so a published tag is only offered if it's strictly newer than what's installed.

Bump `MARKETING_VERSION` in `project.yml` before each release. `release-testing.sh` reads it back out, tags `testing-<version>`, and uses the same value as the Mac DMG name and Windows installer name.

## Cutting a release

```bash
git checkout loom-testing-edition
git pull origin loom-testing-edition
# Bump MARKETING_VERSION in project.yml.
# Update docs/releasing/current-release-notes.md.
# Commit, then:
bin/release-testing.sh
```

The script:

1. Reads `MARKETING_VERSION` from `project.yml` (must be `MAJOR.MINOR.PATCH`).
2. Runs `xcodegen` and `xcodebuild` with that version. The Mac app's `CFBundleShortVersionString` lands at the same value.
3. Packages `LoomTestingEdition-<version>.dmg` with a `.sha256` sidecar.
4. Tags the commit `testing-<version>` and pushes.
5. Creates or updates a GitHub release marked as **pre-release** with `docs/releasing/current-release-notes.md` in the release body (so the stable app's `/releases/latest` query never sees it).
6. Windows CI picks the tag up, builds NSIS installers for x64 + arm64 with `LOOM_BUILD_CODE=<version>` injected at compile time, and appends them to the same release.

`/releases/latest` keeps pointing at the most recent `v*` main build. Testing users see updates through the dedicated `testing-*` query.

## Layout of the changes

- `project.yml` renames target to `LoomTestingEdition`, sets `PRODUCT_NAME = "Loom Testing Edition"` and `PRODUCT_BUNDLE_IDENTIFIER = com.chasesims.LoomTestingEdition`. `MARKETING_VERSION` is the single source of truth for the user-visible version.
- `Loom/App/UpdateService.swift` switches `appSupportRoot` to `Loom Testing Edition`, `installedBundleURL` to `/Applications/Loom Testing Edition.app`, and the update fetcher to walk `/releases` filtered by the `testing-` prefix. The comparison uses `GitHubReleaseFetcher.isNewer` so only strictly newer semvers are offered.
- `Loom/App/GitHubReleaseFetcher.swift` adds `fetchLatestPrerelease(repo:tagPrefix:)` and teaches `versionTag` about the `testing-` prefix.
- Logger subsystems and Keychain service identifier flip from `com.chasesims.Loom` to `com.chasesims.LoomTestingEdition` so neither edition's data leaks into the other.
- `windows-tauri/src-tauri/build.rs` reads `LOOM_BUILD_CODE` from the environment and exposes it as a compile-time env var the Rust code reads via `env!("LOOM_BUILD_CODE")`.
- `windows-tauri/src-tauri/src/updater.rs` walks the 30 most recent releases, picks the newest `testing-*` tag, and offers it when its stripped semver differs from the running version.
- `.github/workflows/windows-release.yml` triggers on `testing-*` tags only, derives the version from the tag, and publishes as a pre-release.
- `bin/release-testing.sh` orchestrates the Mac side of a release end-to-end.

## What this branch does NOT do

- Does not modify main. The branch diverged from `main` at the v3.1.4 cut and never lands back upstream automatically. To pull main into testing, `git merge main` deliberately. To pull testing into main, cherry-pick the specific commits you want.
- Does not change the documentation site or the main `README.md` (those describe the stable channel).
- Does not change app icons. The macOS AppIcon set and Windows `icon.ico` stay the originals so the visual brand carries across. Identity is in the name, bundle ID, and build code, not the artwork.
