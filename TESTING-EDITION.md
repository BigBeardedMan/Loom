# Loom Testing Edition

Testing Edition is the pre-release channel on the `loom-testing-edition`
branch. Stable Loom 9 now includes the feature set that was proven there; this
file remains as the branch/channel reference for future test cuts.

## Channel differences

| | Stable Loom | Testing Edition |
| --- | --- | --- |
| Branch | `main` | `loom-testing-edition` |
| macOS bundle ID | `com.chasesims.Loom` | `com.chasesims.LoomTestingEdition` |
| Windows identifier | `com.chasesims.Loom` | `com.chasesims.LoomTestingEdition` |
| App display name | `Loom` | `Loom Testing Edition` |
| macOS install | `/Applications/Loom.app` | `/Applications/Loom Testing Edition.app` |
| macOS data folder | `~/Library/Application Support/Loom/` | `~/Library/Application Support/Loom Testing Edition/` |
| Release tag | `vX.Y.Z` | `testing-X.Y.Z` |
| GitHub release flag | latest stable release | pre-release |

The two installs do not share app data, Keychain service names, staging
folders, or release tags. Keep channel-specific metadata isolated when moving
features between branches.

## Releasing

Stable releases are cut from `main` with `bin/release.sh`. Testing releases are
cut from `loom-testing-edition` with `bin/release-testing.sh`.

Before any release:

- Bump the version in the branch's project/package metadata.
- Update `docs/releasing/current-release-notes.md`.
- Commit and push the branch.
- Publish and verify the GitHub Release assets, not just the source branch.

## Porting changes

When moving Testing Edition work into stable Loom, keep the feature code but
convert the channel identity back to stable Loom:

- `project.yml` target `Loom`, product name `Loom`, bundle ID `com.chasesims.Loom`.
- `Loom/Info.plist` bundle name and display name `Loom`.
- macOS updater paths under `~/Library/Application Support/Loom/` and
  `/Applications/Loom.app`.
- Windows product name `Loom`, identifier `com.chasesims.Loom`, endpoint
  `latest-windows.json`, and stable `v*` release tags.
- Production signing accounts in `bin/release.sh`.
