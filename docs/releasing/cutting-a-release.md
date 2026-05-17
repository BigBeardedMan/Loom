# Cutting a Testing Edition release

Testing Edition's release script is `bin/release-testing.sh`. It bumps
nothing for you: bump `MARKETING_VERSION` in `project.yml`, update
`docs/releasing/current-release-notes.md`, commit, then run the script.

## Prereqs

- `xcodegen` and `xcodebuild` (Xcode CLI tools).
- `hdiutil` (built-in).
- `gh` CLI authenticated (`gh auth login -h github.com`).
- A clean working tree at the commit you want to tag.

## The flow

```bash
# 1. Bump MARKETING_VERSION in project.yml.
# 2. Update docs/releasing/current-release-notes.md.
# 3. Commit + push.
bin/release-testing.sh         # run from the repo root on loom-testing-edition
```

What the script does:

1. **Reads version** — `MARKETING_VERSION` from `project.yml`.
2. **Pre-flight** — verifies the branch is `loom-testing-edition`, `gh` is authed (via `gh api user`, not `gh auth status` which trips on stale background accounts), the working tree is clean, the local tag doesn't already exist, and whether the GitHub pre-release already exists.
3. **Regenerates the Xcode project** — `xcodegen generate`.
4. **Builds Release** — `xcodebuild -project LoomTestingEdition.xcodeproj -scheme LoomTestingEdition -configuration Release build`.
5. **Locates the built `.app`** — searches `~/Library/Developer/Xcode/DerivedData/.../Build/Products/Release/Loom Testing Edition.app`.
6. **Packages the DMG** — copies `Loom Testing Edition.app` and an `/Applications` alias into a staging temp dir, runs `hdiutil create -format UDZO`, names the file `LoomTestingEdition-<version>.dmg`.
7. **Tags and pushes** — `git tag -a testing-X.Y.Z -m "Loom Testing Edition <version>"`, `git push origin testing-X.Y.Z`.
8. **Creates or updates the GitHub pre-release** — writes notes from `docs/releasing/current-release-notes.md`, then attaches the DMG, checksum, and signature.

The Testing Edition update pill sees the release only after the
`testing-<version>` GitHub pre-release and assets exist. A branch push alone is
not enough.

## Post-release

Every running Testing Edition install picks the new build up through the
Testing Edition update pill after the pre-release is published.

## What can go wrong

- **`error: tag testing-X.Y.Z already exists locally`** — you forgot to bump `MARKETING_VERSION`. Bump it, commit, retry.
- **`error: built Release/Loom Testing Edition.app not found under DerivedData`** — `xcodebuild` failed silently. Re-run with `-quiet` removed from the script to see the actual compile errors.
- **Windows CI created the release first** — the script refreshes the release notes and appends the Mac DMG assets.

## Why ad-hoc signing?

Loom is a personal tool with no Apple Developer Program enrollment. Ad-hoc signing (`CODE_SIGN_IDENTITY: "-"`) is enough for local distribution; users do the right-click → Open dance once and macOS remembers.

If you ever do enroll, change `DEVELOPMENT_TEAM` and `CODE_SIGN_IDENTITY` in `project.yml`. The DMG flow doesn't change.
