# Cutting a Loom release

Stable Loom releases ship from `main` with `bin/release.sh`. Bump
`MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`, update
`docs/releasing/current-release-notes.md`, commit, push, then run the script.

## Prereqs

- `xcodegen` and `xcodebuild` from full Xcode.
- `hdiutil` (built in to macOS).
- `gh` CLI authenticated for `BigBeardedMan/Loom`.
- OpenSSL 3 for signing the checksum sidecar.
- Production release signing keys in Keychain or `~/.loom/release-signing`.
- A clean working tree at the commit you want to tag.

## Flow

```bash
# 1. Bump MARKETING_VERSION and CURRENT_PROJECT_VERSION in project.yml.
# 2. Update docs/releasing/current-release-notes.md.
# 3. Commit + push main.
bin/release.sh
```

What the script does:

1. Reads `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` from `project.yml`.
2. Verifies `gh`, OpenSSL, signing keys, a clean tree, and a free `vX.Y.Z` tag.
3. Regenerates `Loom.xcodeproj` with `xcodegen generate`.
4. Builds `Loom.app` in Release configuration.
5. Validates bundle name, bundle ID, executable, version, and embedded update public key.
6. Packages `Loom-<version>.dmg`.
7. Writes and signs `Loom-<version>.dmg.sha256`.
8. Tags and pushes `v<version>`.
9. Creates or updates the GitHub Release with the DMG, checksum, signature, and release notes.

Windows assets are built by the `Windows Release` GitHub Actions workflow after
the `v<version>` tag is pushed. That workflow appends the x64/arm64 NSIS
installers, installer signatures, `latest-windows.json`, bridge recovery
installers, and legacy installer aliases to the same GitHub Release.

## Compatibility

Loom 9 keeps the stable macOS updater on `/releases/latest` and the Windows
updater on stable `v*` releases. Windows release assets include both
versioned installers (`Loom_<version>_<arch>-setup.exe`) and legacy aliases
(`Loom_<arch>-setup.exe`) so older installed builds can find the update. The
bridge recovery installers are uploaded first so older helpers that select the
first compatible asset can still hand off to the real versioned installer.

## Post-release checks

- `git ls-remote --heads origin main` points at the release commit.
- `git ls-remote --tags origin v<version>` exists.
- `gh release view v<version>` shows the DMG, checksum, signature, Windows
  installers, installer signatures, bridge installers, and `latest-windows.json`.
- The DMG checksum verifies with `shasum -a 256 -c`.
- The Windows Release workflow completes successfully for x64 and arm64.

## Common failures

- `tag vX.Y.Z already exists`: bump `MARKETING_VERSION`, commit, and retry.
- `built app has wrong bundle identifier`: production metadata was overwritten by a testing-channel merge; fix `project.yml` and `Info.plist`.
- `Release is missing a .sha256.sig signature`: the macOS update pill will refuse to stage the DMG until the signature asset exists.
- Windows CI created the release first: `bin/release.sh` appends the DMG assets to the existing release instead of creating a duplicate.
