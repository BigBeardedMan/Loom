# Windows/macOS Parity Task List for 8.2.68

## Scope

This checklist tracks the follow-up parity and updater hardening pass after the 8.2.67 Windows Testing Edition install/update report. The target is the visible Windows/macOS mismatch set called out by testing: missing Settings access, duplicated workspace wording, Recently Deleted placement, and unreliable Windows in-app update behavior.

## macOS Reference Review

- [x] Re-read the macOS workspace sidebar structure in `Loom/Workspace/WorkspaceSidebarView.swift`.
- [x] Confirm macOS workspace rows render the workspace name rather than repeating the workspace kind label.
- [x] Confirm macOS workspace rows do not show an extra Ready subtitle when no folder is assigned.
- [x] Confirm macOS terminal sidebar places Recently Closed above the bottom Recently Deleted control.
- [x] Confirm macOS Recently Deleted uses a separate recovery view with a count badge and Back action.
- [x] Re-check macOS Settings as a top-level, always reachable app surface.
- [x] Compare Windows title bar controls with the macOS top bar and settings entry point.

## Windows Sidebar Corrections

- [x] Remove the Windows-only workspace kind label from workspace row primary text.
- [x] Render the canonical workspace name for Prompt, Ideas, and Review.
- [x] Preserve the workspace kind icon without duplicating the word beside it.
- [x] Remove the fallback Ready subtitle from workspace rows.
- [x] Continue showing the folder path only when a workspace actually has a folder path.
- [x] Keep workspace row selection, color, session count, and usage switching behavior intact.
- [x] Convert the sidebar body to a flex column so terminal recovery controls can pin to the bottom.
- [x] Make Ideas, Review, Recently Deleted, and Terminal sidebar modes respect the same bounded flex layout.
- [x] Keep terminal block lists scrollable without pushing Recently Deleted out of view.
- [x] Place the Recently Deleted button after a flexible spacer so it remains at the bottom of the terminal sidebar section.
- [x] Preserve Recently Closed restore and move-to-deleted actions above the bottom Recently Deleted button.

## Settings Access

- [x] Confirm Windows already had `SettingsModal` mounted and Command Palette settings command wired.
- [x] Add a visible Settings button to the Windows title bar.
- [x] Wire the Settings button to the existing `openSettings` store action.
- [x] Use the shared settings icon from the Windows icon map.
- [x] Keep the Command button, Add Block strip, Dictate button, and Update pill behavior unchanged.
- [x] Typecheck the title bar after adding the new button.

## Updater Root Cause Review

- [x] Review Windows custom updater release selection in `windows-tauri/src-tauri/src/updater.rs`.
- [x] Confirm old code trusted the first matching `testing-*` release from the GitHub API.
- [x] Confirm old code used string inequality instead of strict newer semver comparison.
- [x] Confirm old code accepted any `Loom*_x64-setup.exe` or `Loom*_arm64-setup.exe` asset even if its filename version did not match the release tag.
- [x] Confirm this allowed a `testing-8.2.0` update to point at an older installer asset.
- [x] Confirm old code only checked that the `.sig` asset was present and non-empty.
- [x] Confirm old code did not verify the installer bytes before staging or launching.
- [x] Confirm old helper ran NSIS with plain `/S`.
- [x] Confirm Tauri's own updater uses NSIS updater args `/S /R /UPDATE /ARGS`.
- [x] Confirm old fallback opened the broad GitHub prerelease search URL with `prerelease%3Atrue`.

## Updater Hardening

- [x] Fetch enough recent GitHub releases to avoid depending on the first API item.
- [x] Parse `testing-<version>` tags as strict `MAJOR.MINOR.PATCH` semver.
- [x] Skip draft and non-prerelease releases.
- [x] Require candidate release versions to be strictly newer than the current baked build version.
- [x] Select the highest valid newer Windows release by semver rather than by GitHub ordering.
- [x] Require installer filenames to include a parseable semver.
- [x] Require installer filename semver to match the `testing-*` release tag exactly.
- [x] Require installer architecture suffix to match the native Windows architecture.
- [x] Validate GitHub asset URLs against the expected owner, repo, tag version, and asset name.
- [x] Reject release assets whose URL version and filename version disagree.
- [x] Require a non-empty matching `.sig` asset before offering an update.
- [x] Embed `TAURI_UPDATER_PUBLIC_KEY` into the Rust binary at build time.
- [x] Decode Tauri signer `.sig` assets, including base64-wrapped minisign text.
- [x] Verify downloaded installer bytes with `minisign-verify` before writing the staged marker.
- [x] Re-verify staged installer bytes against the staged signature immediately before launching the helper.
- [x] Remove the staged installer if signature verification fails after download.
- [x] Keep staged marker enforcement so random files in staging cannot be launched.
- [x] Change the Windows helper to run `/S /R /UPDATE /ARGS`.
- [x] Add helper logging for remaining-process closure, installer exit code, and relaunch handling.
- [x] Let NSIS relaunch the app and only use current-exe fallback when the app is not running after install.
- [x] Open the exact `testing-<version>` GitHub release page on install failure.
- [x] Remove the broad prerelease search fallback URL.

## Release Workflow Hardening

- [x] Update Windows workflow wording so build code means semver Testing Edition version.
- [x] Keep `LOOM_BUILD_CODE` sourced from the `testing-*` tag.
- [x] Keep Tauri signing and updater public key requirements enforced in Windows CI.
- [x] Add a Windows CI smoke test that runs the generated NSIS installer with updater flags.
- [x] Confirm the smoke test checks the installed executable exists after the silent install.
- [x] Confirm the smoke test checks the installed product version when Windows reports one.
- [x] Confirm the smoke test stops the relaunched app before artifact upload.

## Versioning

- [x] Bump macOS Testing Edition marketing version to 8.2.68.
- [x] Bump macOS Testing Edition build number to 68.
- [x] Bump Windows package version to 8.2.68.
- [x] Bump Windows Cargo crate version to 8.2.68.
- [x] Bump Windows Tauri bundle version to 8.2.68.
- [x] Bump Windows Cargo lock package version to 8.2.68.
- [x] Update release notes with the parity fixes and updater hardening.

## Local Verification

- [x] Run `pnpm --dir windows-tauri lint`.
- [x] Run `pnpm --dir windows-tauri build`.
- [x] Run focused updater tests with `cargo test --manifest-path windows-tauri/src-tauri/Cargo.toml updater`.
- [x] Add a regression test for semver update comparison.
- [x] Add a regression test for mismatched `testing-*` tag and installer filename version.
- [x] Add a regression test for architecture-specific installer selection.
- [x] Add a regression test for release asset URL version matching.
- [x] Add a regression test for base64 minisign signature decoding.
- [x] Run `cargo check --manifest-path windows-tauri/src-tauri/Cargo.toml`.
- [x] Regenerate the macOS project with `xcodegen generate`.
- [x] Build the macOS Debug app with Xcode and signing disabled.
- [x] Verify built macOS `Info.plist` reports `CFBundleShortVersionString = 8.2.68`.
- [x] Verify built macOS `Info.plist` reports `CFBundleVersion = 68`.

## Release Verification

- [ ] Commit only the intended tracked files.
- [ ] Push `loom-testing-edition` to GitHub.
- [ ] Create the `testing-8.2.68` prerelease.
- [ ] Verify GitHub Actions builds x64 and arm64 Windows installers.
- [ ] Verify GitHub Actions runs the new NSIS updater install smoke test.
- [ ] Verify the GitHub release has the macOS DMG.
- [ ] Verify the GitHub release has x64 and arm64 Windows installers.
- [ ] Verify the GitHub release has matching `.sig` files.
- [ ] Verify the GitHub release has `latest-windows-testing.json`.
- [ ] Verify the release remains marked as a prerelease.
- [ ] Verify the release tag points at the pushed commit.
