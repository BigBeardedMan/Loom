# Cutting a release

Loom's release script is `bin/release.sh`. It bumps nothing for you — bump `MARKETING_VERSION` in `project.yml` first, commit, then run the script.

## Prereqs

- `xcodegen` and `xcodebuild` (Xcode CLI tools).
- `hdiutil` (built-in).
- `gh` CLI authenticated (`gh auth login -h github.com`).
- A clean working tree at the commit you want to tag.

## The flow

```bash
# 1. Bump MARKETING_VERSION (and CURRENT_PROJECT_VERSION) in project.yml.
# 2. Update docs/releasing/current-release-notes.md.
# 3. Commit + push.
bin/release.sh                 # run from the repo root
```

What the script does:

1. **Reads version** — `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` from `project.yml`.
2. **Pre-flight** — verifies `gh` is authed (via `gh api user`, not `gh auth status` which trips on stale background accounts), the local tag doesn't already exist, and the GitHub release doesn't already exist.
3. **Regenerates the Xcode project** — `xcodegen generate`.
4. **Builds Release** — `xcodebuild -project Loom.xcodeproj -scheme Loom -configuration Release build`.
5. **Locates the built `.app`** — searches `~/Library/Developer/Xcode/DerivedData/.../Build/Products/Release/Loom.app`.
6. **Packages the DMG** — copies `Loom.app` and an `/Applications` alias into a staging temp dir, runs `hdiutil create -format UDZO`, names the file `Loom-<version>.dmg`.
7. **Tags and pushes** — `git tag -a vX.Y.Z -m "Loom <version> (<build>)"`, `git push origin vX.Y.Z`.
8. **Creates or updates the GitHub release** — writes the notes from `docs/releasing/current-release-notes.md`, then attaches the DMG, checksum, and signature.

The release notes include `docs/releasing/current-release-notes.md` plus install and auto-update instructions. Keep that file focused on the update you are about to tag; it is the changelog section that appears on the GitHub release.

## Post-release

Every running Loom on every machine picks the new build up via the [auto-update](../updates/auto-update.md) path within 60 seconds.

## What can go wrong

- **`error: tag vX.Y.Z already exists locally`** — you forgot to bump `MARKETING_VERSION`. Bump it, commit, retry.
- **`error: built Release/Loom.app not found under DerivedData`** — `xcodebuild` failed silently. Re-run with `-quiet` removed from the script to see the actual compile errors.
- **`gh release create` 422** — the release already exists on GitHub. Bump version, retry.

## Why ad-hoc signing?

Loom is a personal tool with no Apple Developer Program enrollment. Ad-hoc signing (`CODE_SIGN_IDENTITY: "-"`) is enough for local distribution; users do the right-click → Open dance once and macOS remembers.

If you ever do enroll, change `DEVELOPMENT_TEAM` and `CODE_SIGN_IDENTITY` in `project.yml`. The DMG flow doesn't change.
