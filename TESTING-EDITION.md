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
| Versioning scheme | semver `3.1.4` | alphanumeric `f1ac68e9b2` (first 10 chars of source commit SHA) |
| Release tag | `v3.1.4` | `testing-f1ac68e9b2` |
| GitHub release flag | latest | pre-release |
| Updater | walks `/releases/latest` for `v*` tags | walks `/releases?per_page=30` and picks newest `testing-*` (skipped by `/releases/latest`) |

The two installs cannot see each other's data, keys, or workspaces. Treat them as separate apps that happen to share a repo.

## Why alphanumeric

Testing builds don't have meaningful ordering. Every cut is "just different from the last." Using the git short SHA gives us:

- No manual version bumps. The release script reads the SHA and stamps it everywhere.
- Reproducible identity. The build code maps back to the exact commit it was built from.
- No collisions with main's `v*` tags or with each other.

The updater compares codes for equality, not for ordering. Any pre-release with a `testing-` tag different from yours becomes an offered update.

## Cutting a release

```bash
git checkout loom-testing-edition
git pull origin loom-testing-edition
# Make changes, commit. Then:
bin/release-testing.sh
```

The script:

1. Reads the first 10 chars of `git rev-parse HEAD` as the build code.
2. Runs `xcodegen` and `xcodebuild` with `MARKETING_VERSION=<code>`. The Mac app's `CFBundleShortVersionString` lands at `<code>`.
3. Packages `LoomTestingEdition-<code>.dmg` with a `.sha256` sidecar.
4. Tags the commit `testing-<code>` and pushes.
5. Creates a GitHub release marked as **pre-release** (so the main app's `/releases/latest` query never sees it).
6. Windows CI picks the tag up, builds NSIS installers for x64 + arm64 with `LOOM_BUILD_CODE=<code>` injected at compile time, and appends them to the same release.

`/releases/latest` keeps pointing at the most recent `v*` main build. Testing users see updates through the dedicated `testing-*` query.

## Layout of the changes

- `project.yml` renames target to `LoomTestingEdition`, sets `PRODUCT_NAME = "Loom Testing Edition"` and `PRODUCT_BUNDLE_IDENTIFIER = com.chasesims.LoomTestingEdition`. `MARKETING_VERSION` is the placeholder build code; release-testing.sh overrides it per build.
- `Loom/App/UpdateService.swift` switches `appSupportRoot` to `Loom Testing Edition`, `installedBundleURL` to `/Applications/Loom Testing Edition.app`, and the update fetcher to walk `/releases` filtered by the `testing-` prefix.
- `Loom/App/GitHubReleaseFetcher.swift` adds `fetchLatestPrerelease(repo:tagPrefix:)` and teaches `versionTag` about the `testing-` prefix.
- Logger subsystems and Keychain service identifier flip from `com.chasesims.Loom` to `com.chasesims.LoomTestingEdition` so neither edition's data leaks into the other.
- `windows-tauri/src-tauri/build.rs` reads `LOOM_BUILD_CODE` from the environment and exposes it as a compile-time env var the Rust code reads via `env!("LOOM_BUILD_CODE")`.
- `windows-tauri/src-tauri/src/updater.rs` walks the 30 most recent releases, picks the newest `testing-*` tag, and compares build codes for equality.
- `.github/workflows/windows-release.yml` triggers on `testing-*` tags only, derives the build code from the tag, and publishes as a pre-release.
- `bin/release-testing.sh` orchestrates the Mac side of a release end-to-end.

## What this branch does NOT do

- Does not modify main. The branch diverged from `main` at the v3.1.4 cut and never lands back upstream automatically. To pull main into testing, `git merge main` deliberately. To pull testing into main, cherry-pick the specific commits you want.
- Does not change the documentation site or the main `README.md` (those describe the stable channel).
- Does not change app icons. The macOS AppIcon set and Windows `icon.ico` stay the originals so the visual brand carries across. Identity is in the name, bundle ID, and build code, not the artwork.
